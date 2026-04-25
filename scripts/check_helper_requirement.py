#!/usr/bin/env python3

import re
import sys
from pathlib import Path


def normalize(value: str) -> str:
    stripped = value.strip()
    if stripped.startswith('"') and stripped.endswith('"') and len(stripped) >= 2:
        stripped = stripped[1:-1]
    return stripped.strip()


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_helper_requirement.py <build-settings-file> <configuration>", file=sys.stderr)
        return 2

    settings_path = Path(sys.argv[1])
    configuration = sys.argv[2].strip().lower()
    contents = settings_path.read_text(encoding="utf-8")

    match = re.search(r"^\s*SMARTX_ALLOWED_CLIENT_REQUIREMENT\s*=\s*(.*)$", contents, re.MULTILINE)
    if match is None:
        print("SMARTX_ALLOWED_CLIENT_REQUIREMENT is missing from build settings", file=sys.stderr)
        return 1

    requirement = normalize(match.group(1))
    if configuration != "release":
        print(f"{configuration}: helper requirement check skipped")
        return 0

    invalid_placeholder_patterns = (
        "$(",
        "TODO",
        "REPLACE_ME",
        "CHANGE_ME",
        "placeholder",
    )

    if not requirement:
        print("Release helper requirement must not be empty", file=sys.stderr)
        return 1

    if any(pattern in requirement for pattern in invalid_placeholder_patterns):
        print(f"Release helper requirement is unresolved or placeholder-like: {requirement}", file=sys.stderr)
        return 1

    print("Release helper requirement looks non-empty and resolved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
