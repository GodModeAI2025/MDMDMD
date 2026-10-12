#!/bin/zsh
export SESSION="Scriptum Keyboard Recipe"
python3 /private/tmp/claude-501/-Users-markzimmermann-Documents-Codex-2026-10-08-mach-outputs-Skriptum/6e6d7dd9-519b-48eb-8978-233b07b96577/scratchpad/step.py /Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum/docs/qa-keyboard-recipe-20261012/ev "$1" DeviceInteractionSynthesize "$(python3 -c 'import json,sys;print(json.dumps({"interactSessionKey":sys.argv[1],"interactionCommand":sys.argv[2]}))' "$SESSION" "$3")"
