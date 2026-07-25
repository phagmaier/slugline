/// A synthetic 3,000-paragraph screenplay, shared by all three prototypes.
///
/// The point is not realism, it is *shape*: many short paragraphs with
/// per-element indentation, which is what makes a screenplay hostile to a
/// single `TextField` and interesting to measure.
library;

enum ElementKind { sceneHeading, action, character, parenthetical, dialogue, transition }

/// Left indent and width for each element, in characters on the 10-cpi grid
/// (§5.2). The prototypes convert this to pixels with the monospace advance.
const indentChars = <ElementKind, int>{
  ElementKind.sceneHeading: 0,
  ElementKind.action: 0,
  ElementKind.character: 22,
  ElementKind.parenthetical: 16,
  ElementKind.dialogue: 10,
  ElementKind.transition: 45,
};

const widthChars = <ElementKind, int>{
  ElementKind.sceneHeading: 60,
  ElementKind.action: 60,
  ElementKind.character: 33,
  ElementKind.parenthetical: 26,
  ElementKind.dialogue: 35,
  ElementKind.transition: 15,
};

class SyntheticBlock {
  const SyntheticBlock(this.kind, this.text);
  final ElementKind kind;
  final String text;
}

const _locations = ['CAFÉ', 'ROOFTOP', 'SUBWAY PLATFORM', 'KITCHEN', '日本 GARDEN'];
const _names = ['MARÍA', 'DESMOND', 'ELLIE', 'THE STRANGER', 'JUN'];
const _actions = [
  'She sets the cup down without looking at him. Somewhere below, a siren starts and gives up.',
  'He reads the note twice. Folds it. Puts it in the wrong pocket.',
  'Rain finds the one gap in the awning and lands, precisely, on the open book.',
  'Nobody moves. The refrigerator hums, then stops humming, which is worse.',
];
const _lines = [
  "You said you'd call.",
  "I did call. You were — look, it doesn't matter now.",
  'It matters to me. 🎬',
  "Then say the thing you came here to say and let's both go home.",
  'There was never a version of this where I got to be the reasonable one.',
];

/// Builds a document of exactly [count] paragraphs in scene-shaped runs.
List<SyntheticBlock> buildSyntheticScript({int count = 3000}) {
  final blocks = <SyntheticBlock>[];
  var i = 0;
  while (blocks.length < count) {
    final scene = i ~/ 8;
    blocks.add(SyntheticBlock(
      ElementKind.sceneHeading,
      '${scene.isEven ? "INT." : "EXT."} ${_locations[scene % _locations.length]} - '
      '${scene.isEven ? "NIGHT" : "DAY"}',
    ));
    blocks.add(SyntheticBlock(ElementKind.action, _actions[i % _actions.length]));
    for (var beat = 0; beat < 3 && blocks.length < count; beat++) {
      blocks.add(SyntheticBlock(ElementKind.character, _names[(i + beat) % _names.length]));
      if (beat == 1) {
        blocks.add(const SyntheticBlock(ElementKind.parenthetical, '(not looking up)'));
      }
      blocks.add(SyntheticBlock(ElementKind.dialogue, _lines[(i + beat) % _lines.length]));
    }
    blocks.add(SyntheticBlock(ElementKind.action, _actions[(i + 2) % _actions.length]));
    blocks.add(const SyntheticBlock(ElementKind.transition, 'CUT TO:'));
    i++;
  }
  return blocks.sublist(0, count);
}
