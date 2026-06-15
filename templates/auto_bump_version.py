#!/usr/bin/env python3
"""
Auto-bump version for HarmonyOS NEXT projects.
Run before each build to auto-increment version when source files changed.

Detects changes by comparing git status of source files.
If changes detected: versionCode += 10, patch version += 1.
Updates both AppScope/app.json5 and MainPage.ets APP_VERSION constant.

Usage:
  python3 auto_bump_version.py        # normal run
  python3 auto_bump_version.py --dry-run  # preview only
  python3 auto_bump_version.py --force    # bump even without changes

Place this script in your project root next to build-profile.json5.
"""

import json
import re
import os
import sys
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
APP_JSON5 = os.path.join(PROJECT_ROOT, "AppScope", "app.json5")
MAIN_PAGE_GLOB = os.path.join(PROJECT_ROOT, "entry", "src", "main", "ets", "pages")
APP_VERSION_PATTERN = re.compile(r"APP_VERSION:\s*string\s*=\s*'(\d+\.\d+\.\d+)'")

# Source files that trigger a version bump when changed
WATCH_PATTERNS = [
    "entry/src/main/ets/",
    "AppScope/app.json5",
    "entry/src/main/resources/",
]


def find_main_page():
    """Find the file containing APP_VERSION constant."""
    if not os.path.isdir(MAIN_PAGE_GLOB):
        return None
    for root, dirs, files in os.walk(MAIN_PAGE_GLOB):
        for f in files:
            if f.endswith(".ets"):
                path = os.path.join(root, f)
                if APP_VERSION_PATTERN.search(open(path).read()):
                    return path
    return None


def git_has_changes():
    """Check if any watched source files have uncommitted changes."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True, text=True, cwd=PROJECT_ROOT, timeout=10
        )
        changed = result.stdout.strip().split("\n") if result.stdout.strip() else []
        for file in changed:
            for pattern in WATCH_PATTERNS:
                if pattern in file:
                    return True
        return False
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return True  # no git — always bump


def read_json5(path):
    with open(path, "r") as f:
        return f.read()


def write_file(path, text):
    with open(path, "w") as f:
        f.write(text)


def bump_version(dry_run=False, force=False):
    """Bump patch version. Returns True if bumped."""
    if not os.path.exists(APP_JSON5):
        print(f"ERROR: {APP_JSON5} not found")
        return False

    raw_text = read_json5(APP_JSON5)

    # Extract current version
    m_vc = re.search(r'"versionCode":\s*(\d+)', raw_text)
    m_vn = re.search(r'"versionName":\s*"([^"]+)"', raw_text)
    if not m_vc or not m_vn:
        print("ERROR: Could not parse version fields from app.json5")
        return False

    old_vc = int(m_vc.group(1))
    old_vn = m_vn.group(1)
    parts = [int(x) for x in old_vn.split(".")]
    parts[-1] += 1
    new_vn = ".".join(str(p) for p in parts)
    new_vc = old_vc + 10

    if dry_run:
        print(f"[DRY RUN] Would bump: {old_vn} (code {old_vc}) -> {new_vn} (code {new_vc})")
        return True

    # Update app.json5
    raw_text = re.sub(r'"versionCode":\s*\d+', f'"versionCode": {new_vc}', raw_text)
    raw_text = re.sub(r'"versionName":\s*"[^"]+"', f'"versionName": "{new_vn}"', raw_text)
    write_file(APP_JSON5, raw_text)

    # Update MainPage.ets (or wherever APP_VERSION is defined)
    main_page = find_main_page()
    if main_page:
        ets_text = read_json5(main_page)
        ets_text = re.sub(
            r"APP_VERSION:\s*string\s*=\s*'[^']+'",
            f"APP_VERSION: string = '{new_vn}'",
            ets_text,
        )
        write_file(main_page, ets_text)

    print(f"Bumped: {old_vn} (code {old_vc}) -> {new_vn} (code {new_vc})")
    return True


def main():
    dry_run = "--dry-run" in sys.argv
    force = "--force" in sys.argv

    if not force and not git_has_changes() and not dry_run:
        print("No source changes detected, skipping version bump.")
        return

    bump_version(dry_run=dry_run, force=force)


if __name__ == "__main__":
    main()
