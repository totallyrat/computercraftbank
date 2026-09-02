#!/usr/bin/env bash
# Runs every host-side test. Needs a Lua 5.2+ interpreter (the tests use
# table.unpack); ComputerCraft itself is not required.
set -uo pipefail
cd "$(dirname "$0")/../tests"

LUA="${LUA:-}"
if [ -z "$LUA" ]; then
    for candidate in lua5.4 lua5.3 lua5.2 lua; do
        if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
    done
fi
if [ -z "$LUA" ]; then
    echo "No Lua interpreter found. Install lua5.3 or set LUA=<path>." >&2
    exit 1
fi

failed=0
for test in host_*.lua; do
    printf '%-44s' "$test"
    if output=$("$LUA" "$test" 2>&1); then
        echo "PASS"
    else
        echo "FAIL"
        echo "$output" | sed 's/^/    /'
        failed=$((failed + 1))
    fi
done

if [ "$failed" -gt 0 ]; then
    echo "$failed test(s) failed."
    exit 1
fi
echo "All tests passed."
