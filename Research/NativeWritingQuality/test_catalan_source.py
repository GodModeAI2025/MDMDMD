import unittest
from verify_catalan_source import transform


class CatalanSourceTests(unittest.TestCase):
    def test_all_lemma_tag_pairs_are_expanded(self):
        self.assertEqual(transform(b"form lemma1 TAG1 lemma2 TAG2\n"),
                         {"form\tlemma1\tTAG1", "form\tlemma2\tTAG2"})

    def test_only_documented_verb_exclusions_are_removed(self):
        rows = transform(b"forma aguar TAG\nforma altra TAG\naguar altra TAG\n")
        self.assertEqual(rows, {"forma\taltra\tTAG", "aguar\taltra\tTAG"})

    def test_incomplete_source_pairs_are_not_silently_discarded(self):
        with self.assertRaises(ValueError): transform(b"form lemma TAG orphan\n")

    def test_unicode_and_exact_tags_survive_deduplication(self):
        raw = "cafè cafè NCMS000\ncafè cafè NCMS000\n".encode()
        self.assertEqual(transform(raw), {"cafè\tcafè\tNCMS000"})


if __name__ == "__main__":
    unittest.main()
