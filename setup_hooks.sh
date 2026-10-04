#!/bin/bash
# Points Git at this project's .githooks/ directory and installs what those
# hooks need to run.
#
# Run once after cloning:
#   ./setup_hooks.sh
#
# What you get:
#   pre-commit — formats staged Dart and sorts its imports; syncs templates
#                into pubspec.yaml and sorts dependencies when those changed.
#                A few seconds; runs on every commit. No analysis — that is
#                the IDE's and pre-push's.
#   pre-push   — `dart analyze` and the tests, the same gates CI runs, for
#                what the push changes: none for docs, the packages only when
#                packages/ changed.
#
# Both live in .githooks/, which is committed — unlike .git/hooks/, which is
# why `git config core.hooksPath` exists at all.
set -e

echo "==> Pointing Git at .githooks/..."
git config core.hooksPath .githooks
chmod -R +x .githooks

# pre-commit shells out to better_imports, which is a globally activated
# package rather than a dev_dependency (it rewrites files, so it is a tool,
# not something the build needs). Without this check a fresh clone gets a
# working hook that fails on its very first commit, with an error that reads
# like a project problem rather than a missing tool.
echo "==> Checking the tools the hooks need..."
if dart pub global list 2>/dev/null | grep -q '^better_imports '; then
    echo "    better_imports: already installed"
else
    echo "    better_imports: installing..."
    dart pub global activate better_imports
fi

# `dart pub global run` works regardless, but the warning is worth surfacing
# once here rather than leaving someone to wonder later.
case ":$PATH:" in
    *":$HOME/.pub-cache/bin:"*) ;;
    *) echo "    note: ~/.pub-cache/bin is not on your PATH (the hooks don't need it, but pub will warn)" ;;
esac

# Packages resolve their siblings from the checkouts, as the app and CI do, so
# a package's tests run against the submodule commits rather than a git
# branch. Leaves any pubspec_overrides.yaml you already have alone.
echo "==> Linking packages to their siblings..."
tools/link_packages.sh

echo "✅ Git hooks are active. Commit runs formatting; push runs analyze + tests."
echo "   Bypass either with --no-verify when you have a reason."
