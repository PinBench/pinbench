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
# A package is linked to every sibling it reaches, directly or through other
# siblings: overrides apply only at the root of a resolve, so pinbench_sim must
# override pinbench_pdl itself, which it reaches only through pinbench_parts.
# Only those: pub records an override in the lockfile even when nothing
# depends on it, so listing every sibling filled composite_plugin's tracked
# pubspec.lock with packages it never uses.
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
  # The siblings this package reaches: a breadth-first walk over the sibling
  # names each pubspec mentions as a dependency key.
  reached=()
  queue=("$dir")
  while [ "${#queue[@]}" -gt 0 ]; do
    current="${queue[0]}"
    queue=("${queue[@]:1}")
    for other in "${packages[@]}"; do
      other_name="${other%%	*}"
      other_dir="packages/${other#*	}"
      [ "$other_name" = "$name" ] && continue
      case " ${reached[*]-} " in *" $other_name "*) continue ;; esac
      if grep -qE "^[[:space:]]+${other_name}:" "$current/pubspec.yaml"; then
        reached+=("$other_name")
        queue+=("$other_dir")
      fi
    done
  done
  if [ "${#reached[@]}" -eq 0 ]; then
    echo "  $dir: depends on no sibling"
    continue
  fi
  {
    echo "# Written by tools/link_packages.sh — the sibling checkouts the app builds."
    echo "dependency_overrides:"
    for other in "${packages[@]}"; do
      other_name="${other%%	*}"
      case " ${reached[*]} " in *" $other_name "*) ;; *) continue ;; esac
      echo "  $other_name:"
      echo "    path: ../${other#*	}"
    done
  } > "$out"
  echo "  $dir: linked to ${reached[*]}"
done
