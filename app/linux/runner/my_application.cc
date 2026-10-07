#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean is_window_control(const gchar* button) {
  return g_strcmp0(button, "minimize") == 0 ||
         g_strcmp0(button, "maximize") == 0 ||
         g_strcmp0(button, "close") == 0;
}

static gboolean has_window_control(const gchar* layout) {
  gchar** buttons = g_strsplit(layout, ",", -1);
  gboolean found = FALSE;
  for (gchar** button = buttons; *button != nullptr; button++) {
    if (is_window_control(*button)) {
      found = TRUE;
      break;
    }
  }
  g_strfreev(buttons);
  return found;
}

// Add the complete control group without disturbing menu/icon placement. GTK's
// decoration setting chooses the side; the order within that side follows the
// platform convention.
static gchar* decoration_side_with_controls(const gchar* layout,
                                            gboolean add_controls,
                                            gboolean controls_on_left) {
  gchar** buttons = g_strsplit(layout, ",", -1);
  GString* result = g_string_new(nullptr);
  gboolean controls_added = FALSE;
  const gchar* controls = controls_on_left
                              ? "close,minimize,maximize"
                              : "minimize,maximize,close";

  for (gchar** button = buttons; *button != nullptr; button++) {
    const gchar* value = *button;
    if (is_window_control(value)) {
      if (add_controls && !controls_added) {
        if (result->len > 0) g_string_append_c(result, ',');
        g_string_append(result, controls);
        controls_added = TRUE;
      }
      continue;
    }
    if (*value == '\0') continue;
    if (result->len > 0) g_string_append_c(result, ',');
    g_string_append(result, value);
  }
  if (add_controls && !controls_added) {
    if (result->len > 0) g_string_append_c(result, ',');
    g_string_append(result, controls);
  }

  g_strfreev(buttons);
  return g_string_free(result, FALSE);
}

static gchar* decoration_layout_with_window_controls(GtkWidget* header_bar) {
  gchar* preferred = nullptr;
  g_object_get(gtk_widget_get_settings(header_bar), "gtk-decoration-layout",
               &preferred, nullptr);
  gchar** sides = g_strsplit(preferred == nullptr ? "" : preferred, ":", 2);
  const gchar* left = sides[0] == nullptr ? "" : sides[0];
  const gchar* right = sides[1] == nullptr ? "" : sides[1];
  const gboolean controls_on_left = has_window_control(left);

  gchar* decorated_left =
      decoration_side_with_controls(left, controls_on_left, TRUE);
  gchar* decorated_right =
      decoration_side_with_controls(right, !controls_on_left, FALSE);
  gchar* decorated =
      g_strdup_printf("%s:%s", decorated_left, decorated_right);

  g_free(decorated_left);
  g_free(decorated_right);
  g_strfreev(sides);
  g_free(preferred);
  return decorated;
}

// Phase 10's distraction-free mode. Dart owns the preference and editing UI;
// GTK owns the actual Linux window state.
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "setFullscreen") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid-argument", "setFullscreen expects a boolean", nullptr));
    } else {
      if (fl_value_get_bool(args)) {
        gtk_window_fullscreen(window);
      } else {
        gtk_window_unfullscreen(window);
      }
      response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send window response: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Keep GNOME's header bar; elsewhere leave decoration to the compositor.
  // XDG_CURRENT_DESKTOP is a colon-separated list (e.g. ubuntu:GNOME).
  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  gchar** desktops = g_strsplit(desktop == nullptr ? "" : desktop, ":", -1);
  gboolean use_header_bar = FALSE;
  for (gchar** name = desktops; *name != nullptr; name++) {
    if (g_ascii_strcasecmp(*name, "GNOME") == 0) {
      use_header_bar = TRUE;
      break;
    }
  }
  g_strfreev(desktops);
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    use_header_bar = g_strcmp0(wm_name, "GNOME Shell") == 0;
  }
#endif
  gtk_window_set_title(window, SLUGLINE_APP_NAME);
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, SLUGLINE_APP_NAME);
    gchar* decoration_layout =
        decoration_layout_with_window_controls(GTK_WIDGET(header_bar));
    gtk_header_bar_set_decoration_layout(header_bar, decoration_layout);
    g_free(decoration_layout);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    // As the window's titlebar, GTK makes the blank area draggable and applies
    // the platform's gtk-titlebar-double-click action (normally maximize).
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  gtk_window_set_default_size(window, 1280, 720);
  // A floor, not a preference. The app bar's actions and the element bar along
  // the bottom are laid out in one row each, and below roughly this width the
  // chrome has nowhere left to put them. A tiling window manager is free to
  // ignore this hint — the bars ellipsize rather than overflow so that it
  // degrades into unreadable-but-intact rather than clipped.
  GdkGeometry minimum;
  minimum.min_width = 800;
  minimum.min_height = 480;
  gtk_window_set_geometry_hints(window, nullptr, &minimum, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      messenger, "slugline/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, window, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// `--version` and `--help`, answered here rather than in Dart.
//
// By the time `main()` runs in the Dart VM the engine is up and the window is
// on its way to the screen, so a `--version` handled there would flash a window
// before printing. These two are the whole of the command line that does not
// start an editor; everything else — a file to open — is forwarded to Dart
// untouched.
//
// Returns true when it printed something and the process should stop.
static gboolean handle_information_options(gchar** arguments) {
  for (gchar** argument = arguments; *argument != nullptr; argument++) {
    // A `--` ends the options, so a screenplay honestly called `--help.fountain`
    // is still openable.
    if (g_strcmp0(*argument, "--") == 0) {
      return FALSE;
    }
    if (g_strcmp0(*argument, "--version") == 0 || g_strcmp0(*argument, "-v") == 0) {
      g_print("slugline %s\n", SLUGLINE_VERSION);
      return TRUE;
    }
    if (g_strcmp0(*argument, "--help") == 0 || g_strcmp0(*argument, "-h") == 0) {
      g_print(
          "slugline %s — a keyboard-driven Fountain screenplay editor\n"
          "\n"
          "Usage:\n"
          "  slugline [FILE]\n"
          "\n"
          "Arguments:\n"
          "  FILE          A Fountain screenplay to open. It is created if it\n"
          "                does not exist. Without one, the library opens.\n"
          "\n"
          "Options:\n"
          "  -h, --help    Print this and exit.\n"
          "  -v, --version Print the version and exit.\n"
          "\n"
          "Files are plain Fountain and are never written anywhere but where you\n"
          "put them. Preferences, the library index, the crash journal and the\n"
          "rolling backups live under $XDG_CONFIG_HOME, $XDG_DATA_HOME and\n"
          "$XDG_STATE_HOME, all defaulting to their usual places under $HOME.\n"
          "\n"
          "slugline makes no network connections of any kind.\n",
          SLUGLINE_VERSION);
      return TRUE;
    }
  }
  return FALSE;
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);

  // Before registering, so that neither of these starts an engine or contacts a
  // running instance.
  if (handle_information_options(*arguments + 1)) {
    *exit_status = 0;
    return TRUE;
  }

  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->window_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
