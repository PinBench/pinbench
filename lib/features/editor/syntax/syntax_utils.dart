import 'package:re_highlight/re_highlight.dart';

/// Shared syntax modes used by both PDL and CDL syntax definitions.
final commonSyntaxModes = [
  Mode(scope: 'comment', begin: '//', end: r'$'),
  Mode(scope: 'comment', begin: r'/\*', end: r'\*/'),
  Mode(scope: 'string', begin: '"', end: '"', illegal: r'\n'),
  Mode(scope: 'number', begin: r'\b(-?)\d+(\.\d+)?\b'),
  Mode(scope: 'attr', begin: r'\b[a-zA-Z_]\w*\s*(?=:)'),
];

/// Builds a [Mode] for a circuit-definition language with the given [name],
/// [aliases], and [keywords] structure. The `contains` is always
/// [commonSyntaxModes].
Mode buildSyntaxMode({
  required String name,
  required List<String> aliases,
  required Map<String, List<String>> keywords,
}) => Mode(name: name, aliases: aliases, keywords: keywords, contains: commonSyntaxModes);
