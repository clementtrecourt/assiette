#!/usr/bin/env bash
# Syntax-only check of all Swift sources (no type checking: SwiftUI/SwiftData are not on Linux).
# Usage: tools/check_syntax.sh [files...]
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -eq 0 ]; then mapfile -t files < <(find App/Sources Tests -name '*.swift' 2>/dev/null); else files=("$@"); fi
[ ${#files[@]} -eq 0 ] && { echo "no swift files"; exit 0; }
docker run --rm -v "$PWD":/src:ro -w /src swift:6.0-jammy swiftc -parse "${files[@]}"
echo "syntax OK (${#files[@]} files)"
