# Independent accessibility editor chrome review

**PASS for the frozen PageWritingView layout diff**, pending native accessibility-size/keyboard retest.

ViewThatFits tests the full intrinsic horizontal command row first, so a row wider than available space cannot hide its overflow by compressing the sizing candidate. The fallback splits the validated maximum four commands into two rows, preserves configured order and stable enum IDs, and invokes the same command callback. Visibility/order persistence and source formatting logic are untouched. Native button labels/accessibility identifiers remain intact.

Status count computes once and uses the same value in horizontal/vertical candidates. The vertical fallback allows separate count/goal and saved-status lines rather than truncating a forced horizontal row. Title TextField supports1–3 vertical lines while retaining its binding/accessibility label. No source/journal/block/revision or provider/security behavior changed. Potential title newlines are ordinary editable title data, not executable content.

Actual largest-size narrow window and keyboard-present layout must verify the fallback leaves editing content and all command touch targets reachable, and that status/title are readable; static fit logic is not a complete Dynamic Type/VoiceOver certification. Original QA14 clipped row evidence is addressed by the new allocation rule. No concrete blocking regression or security defect identified. No source/device mutations performed.
