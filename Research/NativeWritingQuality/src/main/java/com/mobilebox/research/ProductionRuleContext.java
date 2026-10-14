package com.mobilebox.research;

import com.oracle.svm.core.annotate.Substitute;
import com.oracle.svm.core.annotate.TargetClass;
import org.languagetool.rules.TestHackHelper;

/**
 * The native C entry point has no JUnit or PatternRuleTest invocation context.
 * Preserve LanguageTool's production clock and exclude only its test-clock
 * branch. No calendar, date filter, language, or correction rule is replaced.
 */
@TargetClass(TestHackHelper.class)
final class ProductionRuleContext {
    @Substitute
    public static boolean isJUnitTest() { return false; }
}
