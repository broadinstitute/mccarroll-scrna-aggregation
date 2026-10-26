#!/usr/bin/env bash
# Renders the workflow figure of the README: docs/figures/workflow.mmd (Mermaid source) -> docs/figures/workflow.svg.
# Run it after every change to workflow.mmd and commit both files; nothing else regenerates the SVG.
# Needs npx (Node.js). The first run downloads @mermaid-js/mermaid-cli and a headless Chromium, so it needs network access.
# The background is transparent, so the SVG reads on light and dark pages (workflow.mmd sets every node's colors explicitly, see
# docs/development.md). The default HTML labels are kept: with plain SVG text long process names wrap in the middle of a word.
set -euo pipefail

command -v npx >/dev/null || { echo "ERROR: npx not found: install Node.js" >&2; exit 1; }
cd "$(dirname "$0")"
npx -y @mermaid-js/mermaid-cli -i workflow.mmd -o workflow.svg -b transparent
echo "Wrote $(pwd)/workflow.svg"
