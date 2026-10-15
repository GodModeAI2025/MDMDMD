# Replay of completed Ukrainian reconstruction

These commands require the existing pinned archive, isolated dependency directory, Java and decoding dependencies; they do not fetch dependencies. Run from the repository root. Each output directory must be fresh. The example uses unused `run-03`, `comparison-02`, `spelling-03` names; choose other fresh names if they exist.

```sh
cd /Users/markzimmermann/Documents/Codex/2026-10-08/mach/outputs/Skriptum
task_work=/Users/markzimmermann/Documents/Codex/2026-10-08/mach/work
task_uk="$task_work/native-ukrainian-source-20261015/reconstruction"
python3 -B Research/NativeWritingQuality/reconstruct_ukrainian_source.py --work-root "$task_work" --output "$task_uk/run-03" --phase prepare
python3 -B Research/NativeWritingQuality/reconstruct_ukrainian_source.py --work-root "$task_work" --output "$task_uk/run-03" --phase expand
python3 -B Research/NativeWritingQuality/verify_ukrainian_generated.py --work-root "$task_work" --expanded "$task_uk/run-03" --output "$task_uk/comparison-02"
python3 -B Research/NativeWritingQuality/verify_ukrainian_spelling.py --work-root "$task_work" --expanded "$task_uk/run-03" --output "$task_uk/spelling-03"
python3 -B -m unittest discover -s Research/NativeWritingQuality/tests -p test_ukrainian_generated.py -v
```


These commands are retained for a future replay; packaging did not execute them. Current recorded runs are `run-02`, `comparison-01` and `spelling-02` in the retained local reconstruction directory.
