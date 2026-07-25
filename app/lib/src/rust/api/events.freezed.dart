// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CoreEvent()';
}


}

/// @nodoc
class $CoreEventCopyWith<$Res>  {
$CoreEventCopyWith(CoreEvent _, $Res Function(CoreEvent) __);
}


/// Adds pattern-matching-related methods to [CoreEvent].
extension CoreEventPatterns on CoreEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreEvent_SaveStateChanged value)?  saveStateChanged,TResult Function( CoreEvent_AutosaveFailed value)?  autosaveFailed,TResult Function( CoreEvent_FileChangedOnDisk value)?  fileChangedOnDisk,TResult Function( CoreEvent_BackupWritten value)?  backupWritten,TResult Function( CoreEvent_EntityIndexUpdated value)?  entityIndexUpdated,TResult Function( CoreEvent_JournalBroken value)?  journalBroken,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged() when saveStateChanged != null:
return saveStateChanged(_that);case CoreEvent_AutosaveFailed() when autosaveFailed != null:
return autosaveFailed(_that);case CoreEvent_FileChangedOnDisk() when fileChangedOnDisk != null:
return fileChangedOnDisk(_that);case CoreEvent_BackupWritten() when backupWritten != null:
return backupWritten(_that);case CoreEvent_EntityIndexUpdated() when entityIndexUpdated != null:
return entityIndexUpdated(_that);case CoreEvent_JournalBroken() when journalBroken != null:
return journalBroken(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreEvent_SaveStateChanged value)  saveStateChanged,required TResult Function( CoreEvent_AutosaveFailed value)  autosaveFailed,required TResult Function( CoreEvent_FileChangedOnDisk value)  fileChangedOnDisk,required TResult Function( CoreEvent_BackupWritten value)  backupWritten,required TResult Function( CoreEvent_EntityIndexUpdated value)  entityIndexUpdated,required TResult Function( CoreEvent_JournalBroken value)  journalBroken,}){
final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged():
return saveStateChanged(_that);case CoreEvent_AutosaveFailed():
return autosaveFailed(_that);case CoreEvent_FileChangedOnDisk():
return fileChangedOnDisk(_that);case CoreEvent_BackupWritten():
return backupWritten(_that);case CoreEvent_EntityIndexUpdated():
return entityIndexUpdated(_that);case CoreEvent_JournalBroken():
return journalBroken(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreEvent_SaveStateChanged value)?  saveStateChanged,TResult? Function( CoreEvent_AutosaveFailed value)?  autosaveFailed,TResult? Function( CoreEvent_FileChangedOnDisk value)?  fileChangedOnDisk,TResult? Function( CoreEvent_BackupWritten value)?  backupWritten,TResult? Function( CoreEvent_EntityIndexUpdated value)?  entityIndexUpdated,TResult? Function( CoreEvent_JournalBroken value)?  journalBroken,}){
final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged() when saveStateChanged != null:
return saveStateChanged(_that);case CoreEvent_AutosaveFailed() when autosaveFailed != null:
return autosaveFailed(_that);case CoreEvent_FileChangedOnDisk() when fileChangedOnDisk != null:
return fileChangedOnDisk(_that);case CoreEvent_BackupWritten() when backupWritten != null:
return backupWritten(_that);case CoreEvent_EntityIndexUpdated() when entityIndexUpdated != null:
return entityIndexUpdated(_that);case CoreEvent_JournalBroken() when journalBroken != null:
return journalBroken(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int handle,  bool dirty)?  saveStateChanged,TResult Function( int handle,  SaveFailure failure,  String message)?  autosaveFailed,TResult Function( String path)?  fileChangedOnDisk,TResult Function( int handle,  String path)?  backupWritten,TResult Function( int handle)?  entityIndexUpdated,TResult Function( int handle)?  journalBroken,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged() when saveStateChanged != null:
return saveStateChanged(_that.handle,_that.dirty);case CoreEvent_AutosaveFailed() when autosaveFailed != null:
return autosaveFailed(_that.handle,_that.failure,_that.message);case CoreEvent_FileChangedOnDisk() when fileChangedOnDisk != null:
return fileChangedOnDisk(_that.path);case CoreEvent_BackupWritten() when backupWritten != null:
return backupWritten(_that.handle,_that.path);case CoreEvent_EntityIndexUpdated() when entityIndexUpdated != null:
return entityIndexUpdated(_that.handle);case CoreEvent_JournalBroken() when journalBroken != null:
return journalBroken(_that.handle);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int handle,  bool dirty)  saveStateChanged,required TResult Function( int handle,  SaveFailure failure,  String message)  autosaveFailed,required TResult Function( String path)  fileChangedOnDisk,required TResult Function( int handle,  String path)  backupWritten,required TResult Function( int handle)  entityIndexUpdated,required TResult Function( int handle)  journalBroken,}) {final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged():
return saveStateChanged(_that.handle,_that.dirty);case CoreEvent_AutosaveFailed():
return autosaveFailed(_that.handle,_that.failure,_that.message);case CoreEvent_FileChangedOnDisk():
return fileChangedOnDisk(_that.path);case CoreEvent_BackupWritten():
return backupWritten(_that.handle,_that.path);case CoreEvent_EntityIndexUpdated():
return entityIndexUpdated(_that.handle);case CoreEvent_JournalBroken():
return journalBroken(_that.handle);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int handle,  bool dirty)?  saveStateChanged,TResult? Function( int handle,  SaveFailure failure,  String message)?  autosaveFailed,TResult? Function( String path)?  fileChangedOnDisk,TResult? Function( int handle,  String path)?  backupWritten,TResult? Function( int handle)?  entityIndexUpdated,TResult? Function( int handle)?  journalBroken,}) {final _that = this;
switch (_that) {
case CoreEvent_SaveStateChanged() when saveStateChanged != null:
return saveStateChanged(_that.handle,_that.dirty);case CoreEvent_AutosaveFailed() when autosaveFailed != null:
return autosaveFailed(_that.handle,_that.failure,_that.message);case CoreEvent_FileChangedOnDisk() when fileChangedOnDisk != null:
return fileChangedOnDisk(_that.path);case CoreEvent_BackupWritten() when backupWritten != null:
return backupWritten(_that.handle,_that.path);case CoreEvent_EntityIndexUpdated() when entityIndexUpdated != null:
return entityIndexUpdated(_that.handle);case CoreEvent_JournalBroken() when journalBroken != null:
return journalBroken(_that.handle);case _:
  return null;

}
}

}

/// @nodoc


class CoreEvent_SaveStateChanged extends CoreEvent {
  const CoreEvent_SaveStateChanged({required this.handle, required this.dirty}): super._();
  

 final  int handle;
 final  bool dirty;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_SaveStateChangedCopyWith<CoreEvent_SaveStateChanged> get copyWith => _$CoreEvent_SaveStateChangedCopyWithImpl<CoreEvent_SaveStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_SaveStateChanged&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.dirty, dirty) || other.dirty == dirty));
}


@override
int get hashCode => Object.hash(runtimeType,handle,dirty);

@override
String toString() {
  return 'CoreEvent.saveStateChanged(handle: $handle, dirty: $dirty)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_SaveStateChangedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_SaveStateChangedCopyWith(CoreEvent_SaveStateChanged value, $Res Function(CoreEvent_SaveStateChanged) _then) = _$CoreEvent_SaveStateChangedCopyWithImpl;
@useResult
$Res call({
 int handle, bool dirty
});




}
/// @nodoc
class _$CoreEvent_SaveStateChangedCopyWithImpl<$Res>
    implements $CoreEvent_SaveStateChangedCopyWith<$Res> {
  _$CoreEvent_SaveStateChangedCopyWithImpl(this._self, this._then);

  final CoreEvent_SaveStateChanged _self;
  final $Res Function(CoreEvent_SaveStateChanged) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? dirty = null,}) {
  return _then(CoreEvent_SaveStateChanged(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as int,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class CoreEvent_AutosaveFailed extends CoreEvent {
  const CoreEvent_AutosaveFailed({required this.handle, required this.failure, required this.message}): super._();
  

 final  int handle;
 final  SaveFailure failure;
 final  String message;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_AutosaveFailedCopyWith<CoreEvent_AutosaveFailed> get copyWith => _$CoreEvent_AutosaveFailedCopyWithImpl<CoreEvent_AutosaveFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_AutosaveFailed&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,handle,failure,message);

@override
String toString() {
  return 'CoreEvent.autosaveFailed(handle: $handle, failure: $failure, message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_AutosaveFailedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_AutosaveFailedCopyWith(CoreEvent_AutosaveFailed value, $Res Function(CoreEvent_AutosaveFailed) _then) = _$CoreEvent_AutosaveFailedCopyWithImpl;
@useResult
$Res call({
 int handle, SaveFailure failure, String message
});




}
/// @nodoc
class _$CoreEvent_AutosaveFailedCopyWithImpl<$Res>
    implements $CoreEvent_AutosaveFailedCopyWith<$Res> {
  _$CoreEvent_AutosaveFailedCopyWithImpl(this._self, this._then);

  final CoreEvent_AutosaveFailed _self;
  final $Res Function(CoreEvent_AutosaveFailed) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? failure = null,Object? message = null,}) {
  return _then(CoreEvent_AutosaveFailed(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as int,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as SaveFailure,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_FileChangedOnDisk extends CoreEvent {
  const CoreEvent_FileChangedOnDisk({required this.path}): super._();
  

 final  String path;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_FileChangedOnDiskCopyWith<CoreEvent_FileChangedOnDisk> get copyWith => _$CoreEvent_FileChangedOnDiskCopyWithImpl<CoreEvent_FileChangedOnDisk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_FileChangedOnDisk&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'CoreEvent.fileChangedOnDisk(path: $path)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_FileChangedOnDiskCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_FileChangedOnDiskCopyWith(CoreEvent_FileChangedOnDisk value, $Res Function(CoreEvent_FileChangedOnDisk) _then) = _$CoreEvent_FileChangedOnDiskCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$CoreEvent_FileChangedOnDiskCopyWithImpl<$Res>
    implements $CoreEvent_FileChangedOnDiskCopyWith<$Res> {
  _$CoreEvent_FileChangedOnDiskCopyWithImpl(this._self, this._then);

  final CoreEvent_FileChangedOnDisk _self;
  final $Res Function(CoreEvent_FileChangedOnDisk) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(CoreEvent_FileChangedOnDisk(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_BackupWritten extends CoreEvent {
  const CoreEvent_BackupWritten({required this.handle, required this.path}): super._();
  

 final  int handle;
 final  String path;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_BackupWrittenCopyWith<CoreEvent_BackupWritten> get copyWith => _$CoreEvent_BackupWrittenCopyWithImpl<CoreEvent_BackupWritten>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_BackupWritten&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,handle,path);

@override
String toString() {
  return 'CoreEvent.backupWritten(handle: $handle, path: $path)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_BackupWrittenCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_BackupWrittenCopyWith(CoreEvent_BackupWritten value, $Res Function(CoreEvent_BackupWritten) _then) = _$CoreEvent_BackupWrittenCopyWithImpl;
@useResult
$Res call({
 int handle, String path
});




}
/// @nodoc
class _$CoreEvent_BackupWrittenCopyWithImpl<$Res>
    implements $CoreEvent_BackupWrittenCopyWith<$Res> {
  _$CoreEvent_BackupWrittenCopyWithImpl(this._self, this._then);

  final CoreEvent_BackupWritten _self;
  final $Res Function(CoreEvent_BackupWritten) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? path = null,}) {
  return _then(CoreEvent_BackupWritten(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as int,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_EntityIndexUpdated extends CoreEvent {
  const CoreEvent_EntityIndexUpdated({required this.handle}): super._();
  

 final  int handle;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_EntityIndexUpdatedCopyWith<CoreEvent_EntityIndexUpdated> get copyWith => _$CoreEvent_EntityIndexUpdatedCopyWithImpl<CoreEvent_EntityIndexUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_EntityIndexUpdated&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,handle);

@override
String toString() {
  return 'CoreEvent.entityIndexUpdated(handle: $handle)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_EntityIndexUpdatedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_EntityIndexUpdatedCopyWith(CoreEvent_EntityIndexUpdated value, $Res Function(CoreEvent_EntityIndexUpdated) _then) = _$CoreEvent_EntityIndexUpdatedCopyWithImpl;
@useResult
$Res call({
 int handle
});




}
/// @nodoc
class _$CoreEvent_EntityIndexUpdatedCopyWithImpl<$Res>
    implements $CoreEvent_EntityIndexUpdatedCopyWith<$Res> {
  _$CoreEvent_EntityIndexUpdatedCopyWithImpl(this._self, this._then);

  final CoreEvent_EntityIndexUpdated _self;
  final $Res Function(CoreEvent_EntityIndexUpdated) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,}) {
  return _then(CoreEvent_EntityIndexUpdated(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_JournalBroken extends CoreEvent {
  const CoreEvent_JournalBroken({required this.handle}): super._();
  

 final  int handle;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_JournalBrokenCopyWith<CoreEvent_JournalBroken> get copyWith => _$CoreEvent_JournalBrokenCopyWithImpl<CoreEvent_JournalBroken>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_JournalBroken&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,handle);

@override
String toString() {
  return 'CoreEvent.journalBroken(handle: $handle)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_JournalBrokenCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_JournalBrokenCopyWith(CoreEvent_JournalBroken value, $Res Function(CoreEvent_JournalBroken) _then) = _$CoreEvent_JournalBrokenCopyWithImpl;
@useResult
$Res call({
 int handle
});




}
/// @nodoc
class _$CoreEvent_JournalBrokenCopyWithImpl<$Res>
    implements $CoreEvent_JournalBrokenCopyWith<$Res> {
  _$CoreEvent_JournalBrokenCopyWithImpl(this._self, this._then);

  final CoreEvent_JournalBroken _self;
  final $Res Function(CoreEvent_JournalBroken) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,}) {
  return _then(CoreEvent_JournalBroken(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
