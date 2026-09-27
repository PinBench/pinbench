import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_edition/pinbench_edition.dart';

void main() {
  test('a build from source has no edition', () {
    // The app treats null as "fully local": signed out, no side panel.
    expect(createEdition(), isNull);
  });
}
