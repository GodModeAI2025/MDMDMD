import unittest
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile
from verify_synthesis_rows import source_fingerprint, verify


class SynthesisProofTests(unittest.TestCase):
    def test_only_a_complete_equal_source_proof_can_be_used(self):
        row = {'rows': 17, 'sortedRowsSHA256':'a'*64}
        self.assertEqual(source_fingerprint({'rowsEqual':True,'generated':row,'release':row}),row)
        for proof in [{}, {'rowsEqual':False,'generated':row,'release':row},
                {'rowsEqual':True,'generated':row,'release':dict(row,rows=16)}]:
            with self.assertRaises(ValueError):source_fingerprint(proof)

    def test_invalid_empty_oversized_or_malformed_fingerprints_are_rejected(self):
        for row in [{'rows':0,'sortedRowsSHA256':'a'*64}, {'rows':25_000_001,'sortedRowsSHA256':'a'*64},
                {'rows':True,'sortedRowsSHA256':'a'*64}, {'rows':1,'sortedRowsSHA256':'not a digest'}]:
            with self.assertRaises(ValueError):source_fingerprint({'rowsEqual':True,'generated':row,'release':row})

    def test_complete_rows_and_tag_inventory_are_independent_requirements(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row = 'café\tcafe\u0301\tNCMS000\n'.encode('utf-8')
            decoded = root/'decoded.tsv'; decoded.write_bytes(row)
            fingerprint = {'rows':1, 'sortedRowsSHA256':hashlib.sha256(row).hexdigest()}
            proof = root/'proof.json'
            proof.write_text(json.dumps({'rowsEqual':True,'generated':fingerprint,'release':fingerprint}))
            jar = root/'dictionary.jar'
            def run(name, tags):
                with zipfile.ZipFile(jar, 'w') as archive:
                    archive.writestr('tags.txt', tags)
                return verify(decoded, proof, jar, 'tags.txt', root/name)
            result = run('equal', b'NCMS000\n')
            self.assertTrue(result['allRowsEqual'])
            self.assertTrue(result['tagInventoryEqual'])
            result = run('wrong-tags', b'OTHER\n')
            self.assertTrue(result['allRowsEqual'])
            self.assertFalse(result['tagInventoryEqual'])
            decoded.write_bytes(row.replace(b'cafe\xcc\x81', b'changed'))
            result = run('wrong-lemma', b'NCMS000\n')
            self.assertFalse(result['allRowsEqual'])
            self.assertTrue(result['tagInventoryEqual'])
            with self.assertRaises(ValueError):run('duplicate-tags', b'NCMS000\nNCMS000\n')
            with self.assertRaises(ValueError):run('equal', b'NCMS000\n')


if __name__ == '__main__':unittest.main()
