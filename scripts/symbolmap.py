"""Map every provider-package symbol that a consumer package names.

Reads the provider at the given revision, collects each type-level declaration with its
access level, then searches the consumer tree for each name.
"""
import re
import subprocess
import sys

"""
Usage:
    symbolmap.py [PROVIDER_REPO] [CONSUMER_REPO] [REV] [SOURCES_SUBPATH]

PROVIDER_REPO is the package whose surface is shrinking, CONSUMER_REPO the
package that might name it. Both default to the router and the multitool.
"""
PROVIDER = (
    sys.argv[1] if len(sys.argv) > 1
    else "/Users/wballard/github/swissarmyhammer/FoundationModelsRouter"
)
CONSUMER = (
    sys.argv[2] if len(sys.argv) > 2
    else "/Users/wballard/github/swissarmyhammer/FoundationModelsMultitool"
)
REV = sys.argv[3] if len(sys.argv) > 3 else "main"
SOURCES = sys.argv[4] if len(sys.argv) > 4 else "Sources"

DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(public|open|package|internal|private|fileprivate)?\s*"
    r"(?:final\s+)?(actor|class|struct|enum|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
)


def run(args, cwd):
    return subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, check=False
    ).stdout


def provider_types():
    """Every type the provider declares at REV, as name -> (access, kind, file)."""
    files = run(
        ["git", "ls-tree", "-r", "--name-only", REV, "--", SOURCES],
        PROVIDER,
    ).split()
    found = {}
    for path in files:
        if not path.endswith(".swift"):
            continue
        for line in run(["git", "show", f"{REV}:{path}"], PROVIDER).splitlines():
            hit = DECL.match(line)
            if not hit:
                continue
            access, kind, name = hit.group(1), hit.group(2), hit.group(3)
            access = access or "internal"
            # A private type is unreachable from any other module, thus a name
            # that matches one is always a different type of the same name.
            if access in ("private", "fileprivate"):
                continue
            # A name declared public anywhere wins over a nested internal one.
            if name in found and found[name][0] in ("public", "open"):
                continue
            found[name] = (access, kind, path)
    return found


def consumer_hits(names):
    """name -> list of "path:line" the consumer names it on, tracked files only."""
    out = {}
    for name in names:
        text = run(
            [
                "git", "grep", "-n", "-w", name, "--",
                "Sources", "Tests", "IntegrationTests/Tests", "IntegrationTests/Package.swift",
                "Package.swift",
            ],
            CONSUMER,
        )
        lines = [ln for ln in text.splitlines() if ln.strip()]
        # Drop pure comment lines: the symbol must be named in code somewhere.
        code = [
            ln for ln in lines
            if not re.match(r"^[^:]+:\d+:\s*(///|//|\*)", ln)
        ]
        if code:
            out[name] = code
    return out


def self_declared(name):
    """True when the consumer declares this name itself, so the hit is ambiguous.

    The trailing class is spelled out rather than written `\\b`: git greps with
    POSIX regular expressions, where `\\b` is not a word boundary.
    """
    text = run(
        ["git", "grep", "-nE",
         r"(actor|class|struct|enum|protocol|typealias) " + name + r"([^A-Za-z0-9_]|$)",
         "--", "Sources", "Tests", "IntegrationTests/Tests"],
        CONSUMER,
    )
    return bool(text.strip())


def main():
    types = provider_types()
    hits = consumer_hits(sorted(types))
    rows = []
    for name, sites in sorted(hits.items()):
        access, kind, path = types[name]
        rows.append((name, access, kind, path, sites, self_declared(name)))

    breaks = [r for r in rows if r[1] not in ("public", "open") and not r[5]]
    safe = [r for r in rows if r[1] in ("public", "open") and not r[5]]
    ambiguous = [r for r in rows if r[5]]

    print("provider type declarations at %s: %d" % (REV, len(types)))
    print("named by the consumer: %d" % len(rows))
    print()
    print("=" * 70)
    print("BREAKS WAITING — the consumer names it, the provider does not publish it")
    print("=" * 70)
    for name, access, kind, path, sites, _ in breaks:
        print("\n%s  (%s %s, %s)" % (name, access, kind, path))
        for site in sites:
            print("    %s" % site)
    print()
    print("=" * 70)
    print("AMBIGUOUS — the consumer also declares this name itself; check by hand")
    print("=" * 70)
    for name, access, kind, path, sites, _ in ambiguous:
        print("  %-34s provider: %s %s" % (name, access, kind))
    print()
    print("=" * 70)
    print("SAFE — public at the provider tip (%d)" % len(safe))
    print("=" * 70)
    for name, access, kind, path, sites, _ in safe:
        print("  %-34s %-9s %-9s %d site(s)" % (name, access, kind, len(sites)))


if __name__ == "__main__":
    sys.exit(main())
