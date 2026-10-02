#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Project skills recognized by a local Codex harness. Upstream revisions are in docs/UI_SKILLS.json.
npx --yes skills add https://github.com/anthropics/skills --skill frontend-design --agent codex --yes
npx --yes skills add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max --agent codex --yes
npx --yes skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend --agent codex --yes
npx --yes skills add https://github.com/Dammyjay93/interface-design --skill interface-design --agent codex --yes
