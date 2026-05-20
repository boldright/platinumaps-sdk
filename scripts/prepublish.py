#!/usr/bin/env python3
"""Build a publish-ready snapshot of the Platinumaps Flutter plugin.

For in-repo development a single source of truth lives at
`iOS/platinumaps-sdk/` and `Android/platinumaps-sdk/`, and the
plugin references those via:

  - `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/`
    `Sources/PlatinumapsSDK` (symlink → `../../../../../iOS/platinumaps-sdk/`)
  - `Flutter/platinumaps_flutter_sdk/example` (symlink → `../example`)
  - `Flutter/platinumaps_flutter_sdk/android/build.gradle` (Gradle
    `sourceSets` srcDirs entries pointing at
    `../../../Android/platinumaps-sdk/...`)
  - `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk.podspec`
    (an extra source-file glob pointing at `../../../iOS/platinumaps-sdk/`)

`dart pub publish` only uploads what's under
`Flutter/platinumaps_flutter_sdk/`, so the symlinks and out-of-tree
references die in the published artifact. This script materialises a
self-contained snapshot the upload command can use directly.

Usage:

    python3 scripts/prepublish.py [--output <dir>]

By default writes to `build/publish-snapshot/platinumaps_flutter_sdk/`.
After running, verify with:

    cd build/publish-snapshot/platinumaps_flutter_sdk
    dart pub publish --dry-run

The script is idempotent: re-running rebuilds the snapshot from
scratch.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGIN_REL = "Flutter/platinumaps_flutter_sdk"
ANDROID_SDK_JAVA = "Android/platinumaps-sdk/src/main/java"
ANDROID_SDK_RES = "Android/platinumaps-sdk/src/main/res"


def archive_subtree(rel_path: str, dest_dir: Path) -> None:
    """Extract `rel_path` from `HEAD` into `dest_dir`, stripping the prefix.

    Only git-tracked files are extracted, so build artefacts (`build/`,
    `.dart_tool/`, `Pods/`, etc.) and other gitignored cruft are
    automatically left out of the snapshot.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    strip = rel_path.count("/") + 1
    git_archive = subprocess.Popen(
        ["git", "archive", "HEAD", rel_path, "--format=tar"],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
    )
    tar = subprocess.run(
        ["tar", "-x", "-C", str(dest_dir), f"--strip-components={strip}"],
        stdin=git_archive.stdout,
        check=False,
    )
    git_archive.wait()
    if git_archive.returncode != 0 or tar.returncode != 0:
        raise SystemExit(
            f"failed to extract {rel_path}: "
            f"git_archive={git_archive.returncode} tar={tar.returncode}"
        )


def materialize_symlinks(snapshot: Path, plugin_origin: str) -> None:
    """Replace each symlink under `snapshot` with the git-tracked subtree it
    points at, relative to the source repository.

    `plugin_origin` is the repo-relative path the snapshot was extracted
    from (e.g. `"Flutter/platinumaps_flutter_sdk"`). It's needed because
    symlink targets in the snapshot are stored unchanged (e.g.
    `../example`), but those targets resolve correctly only against the
    symlink's *original* position in the source repository — not against
    its `build/publish-snapshot/...` position. We track the origin of
    each extracted subtree so we can map symlink positions back.
    """
    origins: dict[Path, Path] = {snapshot: REPO_ROOT / plugin_origin}

    while True:
        symlinks = [p for p in snapshot.rglob("*") if p.is_symlink()]
        if not symlinks:
            return
        for sym in symlinks:
            # Find the closest ancestor in `origins` so we know which
            # source-tree subtree this symlink belongs to.
            ancestor = sym.parent
            while ancestor not in origins:
                if ancestor == snapshot.parent:
                    raise SystemExit(
                        f"could not map {sym} back to a source position"
                    )
                ancestor = ancestor.parent

            rel_from_ancestor = sym.relative_to(ancestor)
            source_position = origins[ancestor] / rel_from_ancestor
            target = (source_position.parent / os.readlink(sym)).resolve()
            try:
                target_rel = target.relative_to(REPO_ROOT)
            except ValueError as exc:
                raise SystemExit(
                    f"symlink {sym} points outside the repo ({target}); "
                    "cannot publish"
                ) from exc
            if not (REPO_ROOT / target_rel).is_dir():
                raise SystemExit(
                    f"symlink {sym} points at non-directory {target_rel}; "
                    "prepublish only supports directory symlinks today"
                )
            sym.unlink()
            archive_subtree(str(target_rel).replace(os.sep, "/"), sym)
            origins[sym] = REPO_ROOT / target_rel


def copy_android_sdk_sources(snapshot: Path) -> None:
    """Copy Android SDK Kotlin sources and resources into the plugin's own
    Android source tree, so the in-repo `srcDirs` overrides become
    unnecessary at publish time."""
    archive_subtree(ANDROID_SDK_JAVA, snapshot / "android/src/main/kotlin")
    archive_subtree(ANDROID_SDK_RES, snapshot / "android/src/main/res")


_BUILD_GRADLE_NEEDLE = """    sourceSets {
        main.java.srcDirs += [
            'src/main/kotlin',
            // In-repo development: pull the SDK sources directly so the
            // single library module compiles them in. The publish
            // workflow copies these files into `src/main/kotlin/` before
            // uploading to pub.dev.
            '../../../Android/platinumaps-sdk/src/main/java',
        ]
        main.res.srcDirs += [
            '../../../Android/platinumaps-sdk/src/main/res',
        ]
    }
"""

_BUILD_GRADLE_REPLACEMENT = """    sourceSets {
        main.java.srcDirs += 'src/main/kotlin'
    }
"""


def rewrite_build_gradle(snapshot: Path) -> None:
    """Drop the Android SDK `srcDirs` overrides now that the sources have
    been copied into the plugin's own `src/main/kotlin/` tree."""
    bg = snapshot / "android/build.gradle"
    original = bg.read_text(encoding="utf-8")
    if _BUILD_GRADLE_NEEDLE not in original:
        raise SystemExit(
            f"could not find the in-repo srcDirs block in {bg}; "
            "the script is out of sync with build.gradle"
        )
    bg.write_text(
        original.replace(_BUILD_GRADLE_NEEDLE, _BUILD_GRADLE_REPLACEMENT),
        encoding="utf-8",
    )


_PODSPEC_NEEDLE = """  s.source_files     = [
    'platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/**/*.swift',
    '../../../iOS/platinumaps-sdk/**/*.swift',
  ]
"""

_PODSPEC_REPLACEMENT = (
    "  s.source_files     = 'platinumaps_flutter_sdk/Sources/**/*.swift'\n"
)


def rewrite_podspec(snapshot: Path) -> None:
    """Drop the iOS SDK source glob from the podspec — those `.swift` files
    now live under the plugin's own `Sources/PlatinumapsSDK/` directory."""
    ps = snapshot / "ios/platinumaps_flutter_sdk.podspec"
    original = ps.read_text(encoding="utf-8")
    if _PODSPEC_NEEDLE not in original:
        raise SystemExit(
            f"could not find the in-repo source_files glob in {ps}; "
            "the script is out of sync with the podspec"
        )
    ps.write_text(
        original.replace(_PODSPEC_NEEDLE, _PODSPEC_REPLACEMENT),
        encoding="utf-8",
    )


def write_pubignore(snapshot: Path) -> None:
    """Write an empty `.pubignore` so the snapshot escapes any parent
    `.gitignore`. By default the snapshot lands under `build/`, which the
    repository root's `.gitignore` excludes, and that would make
    `dart pub publish` treat the entire snapshot — including
    `pubspec.yaml` — as hidden.
    """
    (snapshot / ".pubignore").write_text("", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a publish-ready snapshot of the Flutter plugin.",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        # Default to a path *outside* the repository so the snapshot
        # escapes the repository root's `.gitignore` (which lists
        # `build/` and would otherwise cause `dart pub publish` to
        # treat the entire snapshot — including `pubspec.yaml` — as
        # hidden, even with a sibling `.pubignore` in place).
        default=Path("/tmp/platinumaps-publish-snapshot"),
        help="Where to write the snapshot. Defaults to "
        "/tmp/platinumaps-publish-snapshot/.",
    )
    args = parser.parse_args()

    snapshot = args.output / "platinumaps_flutter_sdk"
    if snapshot.exists():
        shutil.rmtree(snapshot)

    archive_subtree(PLUGIN_REL, snapshot)
    materialize_symlinks(snapshot, PLUGIN_REL)
    copy_android_sdk_sources(snapshot)
    rewrite_build_gradle(snapshot)
    rewrite_podspec(snapshot)
    write_pubignore(snapshot)

    print(f"Wrote publish snapshot to: {snapshot}")
    print("Next:")
    print(f"  cd {snapshot}")
    print("  dart pub publish --dry-run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
