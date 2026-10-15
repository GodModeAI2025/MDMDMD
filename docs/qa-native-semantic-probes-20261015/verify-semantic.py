"""Assess frozen, newly authored language probes without deriving expectations from hits."""
from collections import Counter
import hashlib,json
from pathlib import Path
r=Path(__file__).resolve().parent
corpus_raw=(r/'FrozenCorpus.json').read_bytes()
assert hashlib.sha256(corpus_raw).hexdigest()=='520a104fd28d9fd0de12f9e528ed2c767c58ca046a7884720d18ead11f4f9c36'
corpus=json.loads(corpus_raw);records=corpus['records'];pairs=corpus['pairsData']
assert len(pairs)==44 and len(records)==88
assert len({p['pairID'] for p in pairs})==len(pairs)
# This exclusion was recorded by a separate semantic review before engine results.
disputed={'zh-grammar-01':'The Chinese ba-construction is context-sensitive and not reliably ungrammatical.'}


def replaced(source,offset,length,replacement):
 raw=source.encode('utf-16-le')
 if type(offset) is not int or type(length) is not int or offset<0 or length<1 or offset+length>len(raw)//2:
  raise ValueError('Invalid native UTF-16 range')
 # Strict decoding rejects a surrogate split instead of normalizing source text.
 return raw[:offset*2].decode('utf-16-le')+replacement+raw[(offset+length)*2:].decode('utf-16-le')


def validate_oracle(pair):
 t=pair['target'];raw=pair['positive'].encode('utf-16-le')
 assert raw[t['offsetUTF16']*2:(t['offsetUTF16']+t['lengthUTF16'])*2].decode('utf-16-le')==t['text']
 assert replaced(pair['positive'],t['offsetUTF16'],t['lengthUTF16'],pair['acceptedReplacement']) in pair['acceptedCorrectedSentences']
 assert pair['negative'] in pair['acceptedCorrectedSentences']
 assert pair['expectedRuleIDs'] is None
 assert pair['expectedDimension'] in ('grammar','style')


def canonical(response):
 if response.get('warnings',{}).get('incompleteResults') is not False:raise ValueError('Missing/false completeness proof')
 return sorted(json.dumps(m,sort_keys=True,ensure_ascii=False) for m in response['matches'])


def assess(corpus,native,jvm):
 if len(native)!=len(records) or len(jvm)!=len(records):raise ValueError('Incomplete response set')
 outcomes=[]; parity=[]
 for index,(record,n,j) in enumerate(zip(records,native,jvm)):
  if n['language']!=record['language'] or j['language']!=record['language']:raise ValueError('Language identity mismatch')
  parity.append(canonical(n['response'])==canonical(j['response']))
 for index,pair in enumerate(pairs):
  validate_oracle(pair)
  pos,neg=records[2*index:2*index+2]
  assert (pos['pairID'],pos['expectation'],pos['source'])==(pair['pairID'],'positive',pair['positive'])
  assert (neg['pairID'],neg['expectation'],neg['source'])==(pair['pairID'],'negative',pair['negative'])
  positive=native[2*index]['response']['matches'];negative=native[2*index+1]['response']['matches']
  accepted=[];overlapping=[];target=pair['target']
  for match in positive:
   # Validate every returned range even when the rule is unrelated.
   replaced(pair['positive'],match['offset'],match['length'],'')
   if match['offset']<target['offsetUTF16']+target['lengthUTF16'] and match['offset']+match['length']>target['offsetUTF16']:
    overlapping.append(match['rule']['id'])
   for correction in match['replacements']:
    changed=replaced(pair['positive'],match['offset'],match['length'],correction['value'])
    if changed in pair['acceptedCorrectedSentences']:
     accepted.append({'ruleID':match['rule']['id'],'offset':match['offset'],'length':match['length'],
                      'replacement':correction['value'],'result':changed,'issueType':match['rule']['issueType'],'category':match['rule']['category']})
  for match in negative: replaced(pair['negative'],match['offset'],match['length'],'')
  accepted_ids={m['ruleID'] for m in accepted}
  outcome={'pairID':pair['pairID'],'language':pair['language'],'dimension':pair['expectedDimension'],
           'oracleDisputed':pair['pairID'] in disputed,'oracleDisputeReason':disputed.get(pair['pairID']),
           'positiveMatches':len(positive),'targetOverlappingRuleIDs':overlapping,'acceptedFullSentenceCorrections':accepted,
           'negativeMatches':len(negative),'negativeRuleIDs':[m['rule']['id'] for m in negative],
           'acceptedRuleAbsentInNegative':bool(accepted) and all(m['rule']['id'] not in accepted_ids for m in negative),
           'positiveAndCleanControl':bool(accepted) and not negative}
  outcomes.append(outcome)
 summary={}
 for dimension in ('grammar','style'):
  selected=[o for o in outcomes if o['dimension']==dimension and not o['oracleDisputed']]
  summary[dimension]={'eligibleProbes':len(selected),'exactCorrectionOffered':sum(bool(o['acceptedFullSentenceCorrections']) for o in selected),
      'positiveWithCleanNegative':sum(o['positiveAndCleanControl'] for o in selected),
      'noTargetOverlap':sum(not o['targetOverlappingRuleIDs'] for o in selected),'negativeCasesWithAnyFinding':sum(o['negativeMatches']>0 for o in selected)}
 return {'corpusSHA256':hashlib.sha256(corpus_raw).hexdigest(),'cases':len(records),'fullResponseParityCases':sum(parity),
         'parityPassed':all(parity),'expectationsTakenFromObservedMatches':False,'appCorrectionAdmissionVerified':False,
         'externalLinguisticValidation':False,'comprehensive20LanguageCoverageProven':False,
         'scope':'Independent draft probes; style context not passed to engine. Missing style advice is a desired-profile gap, not proof of a linguistic defect. Chinese grammar oracle excluded before response inspection.',
         'summary':summary,'outcomes':outcomes}

if __name__=='__main__':
 native=json.loads((r/'native-responses.json').read_text());jvm=json.loads((r/'jvm-responses.json').read_text())
 result=assess(corpus,native,jvm)
 with (r/'SEMANTIC_RESULTS.json').open('x') as out:json.dump(result,out,ensure_ascii=False,indent=2);out.write('\n')
 print(json.dumps({k:v for k,v in result.items() if k!='outcomes'},ensure_ascii=False,indent=2))
