#!/usr/bin/env bash
# Validate the PIG SysML v2 model and regenerate diagrams/ with OpenSysML + Graphviz.
# Requires: sysml (https://github.com/Open-MBEE/OpenSysML) and dot (Graphviz) on PATH.
set -euo pipefail
cd "$(dirname "$0")"

models=([0-9][0-9]-*.sysml)
out=diagrams
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sysml "${models[@]}" -validate

render=(-render-form dot -render-style cameo -render-compartments most)

# OpenSysML lays out ortho views itself and names the Graphviz engine in a
# "// layout:" header (neato -n2 for pre-positioned views).
sysml "${models[@]}" -render-all "$tmp" "${render[@]}" -render-lines ortho >/dev/null

# The requirements graph reads better left to right, which needs Graphviz to
# lay it out; ortho routing there needs edge labels as xlabels.
sysml "${models[@]}" -render PigViews::requirements "${render[@]}" -o "$tmp/requirements.dot" >/dev/null
sed -E '/->/s/([[,] *)label=/\1xlabel=/' "$tmp/requirements.dot" > "$tmp/PigViews.requirements.dot"

mkdir "$tmp/svg"
for f in "$tmp"/PigViews.*.dot; do
  name=$(basename "$f" .dot)
  name=${name#PigViews.}
  if [[ $name == requirements ]]; then
    engine=(dot -Grankdir=LR -Gsplines=ortho -Gforcelabels=true)
  else
    read -ra engine <<<"$(sed -n 's#^// layout: ##p' "$f")"
  fi
  "${engine[@]}" -Tsvg "$f" -o "$tmp/svg/$name.svg"
done

rm -rf "$out"
mv "$tmp/svg" "$out"

echo "wrote $(ls "$out" | wc -l) files to $(pwd)/$out"
