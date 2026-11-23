#!/usr/bin/env bash
# Graphviz dot for OpenSysML's ortho layout (OPENSYSML_DOT): unflatten first so
# unconnected definitions and wide inheritance fans wrap into rows instead of
# one very wide rank.
set -euo pipefail
[[ "${1:-}" == -V ]] && exec dot -V
unflatten -l 5 -c 3 | dot "$@"
