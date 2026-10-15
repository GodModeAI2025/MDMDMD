#!/usr/bin/env python3
"""Bind a decoded synthesis dictionary to an already verified editable tagger source.

The Java adapter reverses only the documented lemma|POS lookup key and output
form. Canonical rows must equal the complete frozen source proof, not a subset.
No engine/app activation, network, source execution or license approval.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile
from compare_dictionary_archive import file_digest
from verify_portuguese_source import row_fingerprint, sort_rows


def source_fingerprint(proof):
    value = proof.get('generated')
    if proof.get('rowsEqual') is not True or value != proof.get('release') or not isinstance(value, dict):
        raise ValueError('A successful complete source proof is required')
    if type(value.get('rows')) is not int or not 1 <= value['rows'] <= 25_000_000:
        raise ValueError('Invalid source row count')
    if not isinstance(value.get('sortedRowsSHA256'), str) or not re.fullmatch('[0-9a-f]{64}', value['sortedRowsSHA256']):
        raise ValueError('Invalid source row fingerprint')
    return value


def tags_from_rows(path):
    tags = set()
    with path.open('rb') as stream:
        for line in stream:
            # row_fingerprint has already validated every complete UTF-8 row.
            tags.add(line.removesuffix(b'\n').split(b'\t')[2])
            if len(tags) > 10_000:
                raise ValueError('Tag count bound exceeded')
    return tags


def verify(decoded, source_proof, jar, tag_resource, output):
    if output.exists() or source_proof.stat().st_size > 4 * 1024**2:
        raise ValueError('Fresh evidence directory and bounded source proof required')
    expected = source_fingerprint(json.loads(source_proof.read_text()))
    output.mkdir(parents=True, exist_ok=False)
    temporary = output/'sort-temp'; temporary.mkdir()
    canonical = output/'synthesis-sorted.tsv'
    sort_rows(decoded, canonical, temporary)
    actual = row_fingerprint(canonical)
    actual_tags = tags_from_rows(canonical)
    with zipfile.ZipFile(jar) as archive:
        members = [item for item in archive.infolist() if item.filename == tag_resource]
        if len(members) != 1 or members[0].file_size > 1024**2:
            raise ValueError('Unbound or oversized tag inventory')
        raw = archive.read(members[0]); raw.decode('utf-8', errors='strict')
    inventory = raw.splitlines()
    if not inventory or len(inventory) > 10_000 or len(set(inventory)) != len(inventory):
        raise ValueError('Invalid or duplicate tag inventory')
    result = {'sourceProofSHA256': file_digest(source_proof), 'binaryArtifactSHA256':file_digest(jar),
        'decodedSynthesisSHA256':file_digest(decoded), 'source':expected, 'synthesis':actual,
        'allRowsEqual':expected == actual, 'synthesisTags':len(actual_tags),'inventoryTags':len(inventory),
        'tagInventoryEqual':actual_tags == set(inventory), 'tagInventorySHA256':hashlib.sha256(raw).hexdigest(),
        'scope':'Complete synthesis form/lemma/POS equivalence to the frozen editable-source tagger proof and exact tag membership. No FSA-byte, spelling, engine-quality or distribution approval claim.'}
    (output/'RESULT.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['decoded','source-proof','jar','output']:
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--tag-resource',required=True)
    parser.add_argument('--expected-jar-sha256',required=True)
    parser.add_argument('--expected-source-proof-sha256',required=True)
    args=parser.parse_args()
    if file_digest(args.jar) != args.expected_jar_sha256 or file_digest(args.source_proof) != args.expected_source_proof_sha256:
        raise ValueError('Inputs differ from pinned receipts')
    result=verify(args.decoded,args.source_proof,args.jar,args.tag_resource,args.output)
    print(json.dumps(result))
    return 0 if result['allRowsEqual'] and result['tagInventoryEqual'] else 1


if __name__ == '__main__':raise SystemExit(main())
