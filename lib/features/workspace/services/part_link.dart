import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/parser_utils.dart';

/// The catalog part a `/part/<name>` link names, or null if none does.
///
/// Matched the way a `.cdl` type is, with punctuation and spacing dropped, so
/// `MPU-6050`, `mpu6050` and `Accelerometer + Gyro (MPU-6050)` all name the
/// same part; and with case ignored, because a URL is typed by hand. A part's
/// own name or file id wins over an alias, so a word one part uses as an alias
/// cannot take a link away from the part that is called that.
PartModel? partForLink(List<PartModel> catalog, String name) {
  String token(String s) => ParserUtils.typeToken(s).toLowerCase();

  final wanted = token(name);
  if (wanted.isEmpty) return null;

  for (final part in catalog) {
    if (token(part.name) == wanted) return part;
    if (part.definitionId case final id? when token(id) == wanted) return part;
  }
  for (final part in catalog) {
    if (part.aliases.any((alias) => token(alias) == wanted)) return part;
  }
  return null;
}
