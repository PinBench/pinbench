import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_edition_api/host.dart';

void main() {
  group('HostWorkspace', () {
    test('compares by value, so an unchanged workspace does not rebuild a panel', () {
      // hostWorkspaceProvider is rebuilt from the app's workspace state on every
      // change; without value equality a panel listening for a new project
      // would see one on every file save.
      const a = HostWorkspace(path: '/p', mainCircuitPath: '/p/c.cdl', filePaths: ['/p/c.cdl']);
      const b = HostWorkspace(path: '/p', mainCircuitPath: '/p/c.cdl', filePaths: ['/p/c.cdl']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when the files differ', () {
      const a = HostWorkspace(path: '/p', filePaths: ['/p/a.ino']);
      const b = HostWorkspace(path: '/p', filePaths: ['/p/a.ino', '/p/b.cdl']);
      expect(a, isNot(equals(b)));
    });

    test('an empty workspace has no path', () {
      expect(const HostWorkspace().path, isNull);
    });
  });
}
