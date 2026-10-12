#!/bin/zsh
cd /Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum/docs/qa-merged-ui-20261012/$1
shift
for f in "$@"; do echo "-- $f"; grep -nE "Application UI|Device orient|TextField, .*Seitentitel|TextView|blockWritingView|Keyboard Focused|Keyboard,|Window, \{\{0.0, 0.0\}, \{[0-9.]+, [0-9.]+\}\}, hitPoint" $f-hierarchyPath.txt | cut -c1-190 | head -12; done
