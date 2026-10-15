public final class SynthDictionaryRowsTest {
  static void refuses(String key, String form, String tag) {
    try { SynthDictionaryRows.canonicalRow(key, form, tag); }
    catch (IllegalArgumentException expected) { return; }
    throw new AssertionError("Malformed record accepted");
  }
  public static void main(String[] args) {
    String value = SynthDictionaryRows.canonicalRow("cafe\u0301|NCMS000", "café", null);
    if (!value.equals("café\tcafe\u0301\tNCMS000")) throw new AssertionError("Unicode/POS changed");
    if (!SynthDictionaryRows.canonicalRow("dois|Z", "dois", "").equals("dois\tdois\tZ")) throw new AssertionError();
    refuses("lemma", "word", null);
    refuses("|TAG", "word", null);
    refuses("lemma|", "word", null);
    refuses("lemma|TAG|extra", "word", null);
    refuses("lemma|TAG", "", null);
    refuses("lemma|TAG", "word", "unaccounted tag");
    refuses("lemma|TAG", "word\nother", null);
    refuses("lemma\tother|TAG", "word", null);
    refuses("lemma|TAG", "word\0other", null);
    System.out.println("Synthesis adapter: 2 exact rows and 9 malformed-record controls passed");
  }
}
