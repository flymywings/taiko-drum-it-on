import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiko_rhythm_proto/game/judgement_engine.dart';
import 'package:taiko_rhythm_proto/game/key_bindings.dart';

void main() {
  const time = Duration.zero;
  testWidgets('focused game forwards key presses but not repeats',
      (tester) async {
    final hits = <DrumHit>[];
    await tester.pumpWidget(MaterialApp(
      home: GameKeyboard(
        onHit: (color, hand) => hits.add((color: color, hand: hand)),
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    expect(hits, [
      (color: HitColor.blue, hand: Hand.left),
      (color: HitColor.red, hand: Hand.right),
    ]);
  });

  test('D F J K match the four pads from left to right', () {
    expect(
      hitForKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: time,
      )),
      (color: HitColor.blue, hand: Hand.left),
    );
    expect(
      hitForKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        timeStamp: time,
      )),
      (color: HitColor.red, hand: Hand.left),
    );
    expect(
      hitForKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyJ,
        logicalKey: LogicalKeyboardKey.keyJ,
        timeStamp: time,
      )),
      (color: HitColor.red, hand: Hand.right),
    );
    expect(
      hitForKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyK,
        logicalKey: LogicalKeyboardKey.keyK,
        timeStamp: time,
      )),
      (color: HitColor.blue, hand: Hand.right),
    );
  });

  test('repeats, releases, and other keys do not hit', () {
    expect(
      hitForKeyEvent(const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: time,
      )),
      isNull,
    );
    expect(
      hitForKeyEvent(const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: time,
      )),
      isNull,
    );
    expect(
      hitForKeyEvent(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: time,
      )),
      isNull,
    );
  });
}
