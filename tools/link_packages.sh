#!/usr/bin/env bash
# Points every package in packages/ at its siblings' checkouts, so each one is
# built and tested against exactly the code the app builds — the submodule
# commits it pins — rather than against whatever a git dependency's branch
# holds today.
#
# A package checked on its own resolves its pubspec as written, and
# pinbench_parts and pinbench_sim depend on pinbench_pdl and pinbench_cdl by
# git at `main`. So CI tested them against pdl's main while the app built the
# submodule commit — and they did not agree: a branch the app needed passed
# locally (where pubspec_overrides.yaml files point at the checkouts) and
# failed on CI, against an older main without the APIs it used. The root
# pubspec's dependency_overrides already do this for the app; this does the
# same for each package, by writing the pubspec_overrides.yaml pub reads.
#
# Every sibling is listed, not only direct dependencies: overrides apply only
# at the root of a resolve, so pinbench_sim must override pinbench_pdl itself,
# which it reaches only through pinbench_parts. Overrides for packages a
# package never reaches are ignored.
#
# A package that already has a pubspec_overrides.yaml (gitignored; a local
# setup may point ngspice_dart at a checkout too) is left alone unless --force,
# and so is a submodule (pinbench_pdl, pinbench_cdl), which is a repository of
# its own.
#
# Usage:
#   tools/link_packages.sh           # CI, or a fresh clone
#   tools/link_packages.sh --force   # replace existing overrides
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=1 ;;
    -h|--help)  sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

# name<TAB>directory for every package with a pubspec.
packages=()
for dir in packages/*/; do
  dir="${dir%/}"
  [ -f "$dir/pubspec.yaml" ] || continue
  name="$(sed -n 's/^name:[[:space:]]*//p' "$dir/pubspec.yaml" | head -1 | tr -d '\r')"
  [ -n "$name" ] && packages+=("$name	$(basename "$dir")")
done

for entry in "${packages[@]}"; do
  name="${entry%%	*}"
  dir="packages/${entry#*	}"
  out="$dir/pubspec_overrides.yaml"
  # A submodule is another repository, tested standalone by its own CI; a
  # file written into it would only show up as a change there.
  if [ -e "$dir/.git" ]; then
    echo "  $dir: a submodule — left to its own repository"
    continue
  fi
  if [ -f "$out" ] && [ "$FORCE" -eq 0 ]; then
    echo "  $dir: keeping its existing pubspec_overrides.yaml"
    continue
  fi
  {
    echo "# Written by tools/link_packages.sh — the sibling checkouts the app builds."
    echo "dependency_overrides:"
    for other in "${packages[@]}"; do
      other_name="${other%%	*}"
      [ "$other_name" = "$name" ] && continue
      echo "  $other_name:"
      echo "    path: ../${other#*	}"
    done
  } > "$out"
  echo "  $dir: linked to its siblings"
done
