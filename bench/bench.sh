#!/usr/bin/env bash
# Run llama-bench over one or more GGUF files with identical flags, and keep
# the full output in a log.
#
# Usage: bench.sh <model.gguf> [more.gguf ...]
#   LLAMA_PREFIX  install prefix (default ~/.local/share/llama.cpp)
#   OUT           log path (default /tmp/llama-bench-<timestamp>.log)
#   BENCH_ARGS    override the llama-bench arguments
#
# The fixed flags (-ngl 99 -p 512 -n 128 -r 3) are what the numbers in
# RESULTS.md were measured with. Keep them to stay comparable.
#
# Do not pipe llama-bench through grep on the way in: the table is written at
# the end of the run, and a filtered pipe has come back empty. Write the log
# first, then grep it.
set -euo pipefail

[ $# -gt 0 ] || { echo "usage: $0 <model.gguf> [...]" >&2; exit 2; }

LLAMA_PREFIX=${LLAMA_PREFIX:-$HOME/.local/share/llama.cpp}
export LD_LIBRARY_PATH="$LLAMA_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
BENCH=$LLAMA_PREFIX/bin/llama-bench
OUT=${OUT:-/tmp/llama-bench-$(date +%Y%m%d-%H%M%S).log}
BENCH_ARGS=${BENCH_ARGS:--ngl 99 -p 512 -n 128 -r 3}

{
  echo "# llama-bench $(date -Iseconds)"
  echo "# $($BENCH --version 2>/dev/null | head -1)"
  echo "# args: $BENCH_ARGS"
} >"$OUT"

for m in "$@"; do
  echo "## $(basename "$m")" | tee -a "$OUT"
  # shellcheck disable=SC2086
  "$BENCH" -m "$m" $BENCH_ARGS 2>&1 | tee -a "$OUT" >/dev/null
done

echo "log: $OUT"
grep -E '^\|' "$OUT" | grep -vE '^\|[-| ]+\|$'
