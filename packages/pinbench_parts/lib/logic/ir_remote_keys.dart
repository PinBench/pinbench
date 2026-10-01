/// The mini IR remote's twenty buttons and the NEC commands they send.
///
/// This is the remote sold with VS1838B receiver kits; it sends address 0x00
/// and these commands, which are the codes Arduino tutorials print for it
/// (IRremote shows the power key as raw `0xFFA25D`: command 0x45).
abstract final class IrRemoteKeys {
  static const address = 0x00;

  /// Button id → NEC command. The ids are also the remote painter's regions.
  static const commands = <String, int>{
    'power': 0x45,
    'menu': 0x47,
    'test': 0x44,
    'plus': 0x40,
    'back': 0x43,
    'previous': 0x07,
    'play': 0x15,
    'next': 0x09,
    '0': 0x16,
    'minus': 0x19,
    'c': 0x0D,
    '1': 0x0C,
    '2': 0x18,
    '3': 0x5E,
    '4': 0x08,
    '5': 0x1C,
    '6': 0x5A,
    '7': 0x42,
    '8': 0x52,
    '9': 0x4A,
  };
}
