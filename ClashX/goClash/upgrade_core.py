import subprocess
import sys
from build_clash_universal import run


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        fail(
            "This helper is intentionally conservative on the smartx branch.\n"
            "Refusing to edit go.mod without an explicit target version or commit.\n"
            "The embedded core currently uses require + replace module wiring:\n"
            "  require github.com/metacubex/mihomo ...\n"
            "  replace github.com/metacubex/mihomo => github.com/vernesong/mihomo ...\n"
            "Update go.mod manually to the desired github.com/vernesong/mihomo revision,\n"
            "then run build_clash_universal.py. This script does not perform automatic upgrades yet."
        )

    fail(
        f"Refusing to perform an automatic core upgrade to {sys.argv[1]!r}.\n"
        "On the smartx branch, core upgrades must currently be done manually in go.mod\n"
        "so the require + replace layout can be reviewed before rebuilding."
    )
