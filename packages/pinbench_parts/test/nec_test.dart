import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_parts/logic/ir_remote_keys.dart';
import 'package:pinbench_parts/logic/nec.dart';
import 'package:pinbench_parts/painters/ir_remote/ir_remote_painter.dart';

void main() {
  test('a frame is the leader, 32 bits and a stop mark, ending idle high', () {
    final levels = Nec.frame(0x00, 0x45);
    expect(levels.first, (false, Nec.leadMarkUs));
    expect(levels[1], (true, Nec.leadSpaceUs));
    expect(levels, hasLength(2 + 64 + 2));
    expect(levels[levels.length - 2], (false, Nec.bitMarkUs));
    expect(levels.last.$1, isTrue);
    // The same length whatever the code, because every 0 has a 1 in its
    // inverse: 13.5 ms of leader, 16 zeros and 16 ones, and the stop mark.
    final total = levels.fold<double>(0, (t, l) => t + l.$2);
    expect(total, 68062.5);
  });

  test('round-trips every key on the remote', () {
    for (final MapEntry(:key, value: command) in IrRemoteKeys.commands.entries) {
      expect(Nec.decode(Nec.frame(IrRemoteKeys.address, command)), (0, command), reason: key);
    }
  });

  test('the power key is the code tutorials print for it', () {
    // IRremote's legacy raw value 0xFFA25D: address 0x00, command 0x45.
    final levels = Nec.frame(0x00, IrRemoteKeys.commands['power']!);
    var raw = 0;
    for (var i = 0; i < 32; i++) {
      if (levels[2 + 2 * i + 1].$2 == Nec.oneSpaceUs) raw |= 1 << i;
    }
    expect(raw, 0xBA45FF00, reason: 'LSB-first: 00 FF 45 BA');
  });

  test('every button on the remote sends a command, and is hit where it is drawn', () {
    final remote = IrRemotePainter();
    const size = IrRemotePainter.componentSize;
    const scale = 248 / 220;
    Offset at(double x, double y) => Offset((x - 248) * scale, (y - 70) * scale);

    expect(remote.regionAt(at(294, 131), size), 'power');
    expect(remote.regionAt(at(356, 244), size), 'play');
    expect(remote.regionAt(at(418, 470), size), '9');
    expect(remote.regionAt(at(356, 131), size), isNull, reason: 'the gap beside power');
    expect(remote.regionAt(const Offset(4, 4), size), isNull, reason: 'the case, not a button');

    // Hit-testing follows the size the part is drawn at.
    expect(remote.regionAt(at(294, 131) / 2, size / 2), 'power');

    // Every button the painter draws has a code to send.
    for (var y = 0.0; y < size.height; y += 4) {
      for (var x = 0.0; x < size.width; x += 4) {
        final id = remote.regionAt(Offset(x, y), size);
        if (id != null) expect(IrRemoteKeys.commands, contains(id));
      }
    }
  });

  test('pressing a button repaints the remote, and nothing else does', () {
    // A built-in part: no DSL painter compares its properties for it.
    IrRemotePainter remote([String? pressed]) =>
        IrRemotePainter(properties: {'pressedRegion': ?pressed});
    expect(remote('5').shouldRepaint(remote()), isTrue);
    expect(remote().shouldRepaint(remote('5')), isTrue, reason: 'and releasing it');
    expect(remote('5').shouldRepaint(remote('5')), isFalse);
  });
}
