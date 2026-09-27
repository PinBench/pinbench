import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_provider.g.dart';

@Riverpod(keepAlive: true)
class TabsList extends _$TabsList {
  @override
  List<String> build() => [];

  void updateTabs(List<String> tabs) {
    state = tabs;
  }
}

@Riverpod(keepAlive: true)
class ActiveTab extends _$ActiveTab {
  @override
  String build() => '';

  void setActive(String tab) {
    state = tab;
  }
}

@Riverpod(keepAlive: true)
class ActiveContextMenuId extends _$ActiveContextMenuId {
  @override
  String? build() => null;

  void updateId(String? id) {
    state = id;
  }
}
