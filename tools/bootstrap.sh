#!/bin/sh
# Make a checkout ready to analyze, test and run: the format submodules, every
# pub root's dependencies (the app's and each package's), and the generated
# *.g.dart files, which are gitignored. Each step runs only when its result is
# missing, so it is quick on a checkout that is already set up, and safe to
# run again. A new clone, a new worktree and a branch switch that adds a
# package all need it; .githooks/pre-push runs it first.
#
#   tools/bootstrap.sh
set -eu
cd "$(dirname "$0")/.."

# The two format packages are submodules. Without them nothing resolves.
if [ ! -f packages/pinbench_pdl/pubspec.yaml ] || [ ! -f packages/pinbench_cdl/pubspec.yaml ]; then
    echo "🔧 Fetching submodules…"
    git submodule update --init --recursive
fi

for root in . packages/*/; do
    [ -f "$root/pubspec.yaml" ] || continue
    if [ ! -f "$root/.dart_tool/package_config.json" ] || [ "$root/pubspec.yaml" -nt "$root/.dart_tool/package_config.json" ]; then
        echo "🔧 Getting dependencies for ${root}…"
        (cd "$root" && flutter pub get >/dev/null)
    fi
done

# A part file that does not exist yet is code build_runner has not generated.
missing=$(grep -rlE "^part '[^']+\.g\.dart';" lib 2>/dev/null | while read -r source; do
    grep -oE "^part '[^']+\.g\.dart';" "$source" | sed -E "s/^part '(.*)';/\1/" | while read -r part; do
        [ -f "$(dirname "$source")/$part" ] || echo "$source"
    done
done | head -1)
if [ -n "$missing" ]; then
    echo "🔧 Generating code (build_runner)…"
    dart run build_runner build --delete-conflicting-outputs >/dev/null
fi
