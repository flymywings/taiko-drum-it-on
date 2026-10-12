import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'judgement_engine.dart';

typedef DrumHit = ({HitColor color, Hand hand});

class GameKeyboard extends StatelessWidget {
  const GameKeyboard({super.key, required this.onHit, required this.child});

  final void Function(HitColor color, Hand hand) onHit;
  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final hit = hitForKeyEvent(event);
    if (hit == null) return KeyEventResult.ignored;
    onHit(hit.color, hit.hand);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: child,
      );
}

DrumHit? hitForKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.keyD) {
    return (color: HitColor.blue, hand: Hand.left);
  }
  if (key == LogicalKeyboardKey.keyF) {
    return (color: HitColor.red, hand: Hand.left);
  }
  if (key == LogicalKeyboardKey.keyJ) {
    return (color: HitColor.red, hand: Hand.right);
  }
  if (key == LogicalKeyboardKey.keyK) {
    return (color: HitColor.blue, hand: Hand.right);
  }
  return null;
}
