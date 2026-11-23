#!/usr/bin/env bash
# Validate the PIG SysML v2 model and regenerate diagrams/ with OpenSysML + Graphviz.
# Requires: sysml (https://github.com/Open-MBEE/OpenSysML) and dot (Graphviz) on PATH.
set -euo pipefail
cd "$(dirname "$0")"

models=(0*.sysml)
out=diagrams
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sysml "${models[@]}" -validate

sysml "${models[@]}" -render-all "$tmp" -render-form dot -render-style cameo \
  -render-compartments most >/dev/null

mkdir "$tmp/svg"
for f in "$tmp"/PigViews.*.dot; do
  name=$(basename "$f" .dot)
  name=${name#PigViews.}
  args=()
  [[ $name == requirements ]] && args=(-Grankdir=LR)
  dot "${args[@]}" -Tsvg "$f" -o "$tmp/svg/$name.svg"
done

rm -rf "$out"
mv "$tmp/svg" "$out"

echo "wrote $(ls "$out" | wc -l) files to $(pwd)/$out"
