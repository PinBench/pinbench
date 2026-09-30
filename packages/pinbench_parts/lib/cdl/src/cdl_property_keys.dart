import '../../models/part_model.dart';

/// Maps a component `properties` key between its internal (capitalized) form —
/// used verbatim as the properties-panel label and dropdown option — and the
/// lowercase form the `.cdl` presents (`Color` <-> `color`, `Resistance` <->
/// `resistance`), so the file reads consistently (like a wire's `color:`)
/// without changing the keys the panel and painters rely on. Unknown keys pass
/// through unchanged.
abstract final class CdlPropertyKeys {
  static const _internalToCdl = {
    ComponentProps.color: 'color',
    ComponentProps.resistance: 'resistance',
  };
  static final _cdlToInternal = {
    for (final entry in _internalToCdl.entries) entry.value: entry.key,
  };

  static String toCdl(String internalKey) => _internalToCdl[internalKey] ?? internalKey;
  static String toInternal(String cdlKey) => _cdlToInternal[cdlKey] ?? cdlKey;
}
