#!/usr/bin/env python3
"""Read downloaded rule examples and verify an explicitly local engine; no public requests."""
import argparse, html, json, pathlib, re, urllib.parse, urllib.request
p=argparse.ArgumentParser();p.add_argument('--distribution',required=True);p.add_argument('--output',required=True);p.add_argument('--endpoint',default='http://127.0.0.1:8097/v2');a=p.parse_args()
u=urllib.parse.urlparse(a.endpoint)
if u.hostname not in ('127.0.0.1','localhost','::1'): raise SystemExit('Verification permits loopback only')
catalog=json.load(urllib.request.urlopen(a.endpoint+'/languages',timeout=30))
primary={x['code'].split('-')[0].split('_')[0] for x in catalog}
results=[]
for language in sorted(primary):
 path=pathlib.Path(a.distribution)/'org/languagetool/rules'/language/'grammar.xml'
 if not path.exists(): continue
 text=path.read_text(encoding='utf8')
 candidates=re.findall(r'<example\b[^>]*\bcorrection="[^"]*"[^>]*>(.*?)</example>',text,re.S)
 verified=None
 for raw in candidates[:30]:
  example=html.unescape(re.sub('<[^>]*>','',raw)).strip()
  if len(example)>400 or re.search(r'&[a-zA-Z]+;',example): continue
  preferred=next((x['longCode'] for x in catalog if x['code']==language and x['longCode']==language),None) or next((x['longCode'] for x in catalog if x['code']==language),language)
  body=urllib.parse.urlencode({'text':example,'language':preferred}).encode()
  try:
   response=json.load(urllib.request.urlopen(urllib.request.Request(a.endpoint+'/check',data=body),timeout=60))
   substantive=[{'rule':m['rule']['id'],'category':m['rule']['category']['id'],'issueType':m['rule']['issueType'],'offset':m['offset'],'length':m['length'],'replacementCount':len(m['replacements'])} for m in response['matches'] if m['rule']['issueType']!='misspelling']
   if substantive:
    verified={'primaryLanguage':language,'requestedLanguage':preferred,'syntheticRuleExample':example,'version':response['software']['version'],'matches':substantive};break
  except Exception as error:
   print(language,type(error).__name__,flush=True)
 if verified: results.append(verified);print(language,'VERIFIED',verified['matches'][0]['rule'],flush=True)
 else: print(language,'NOT_PROVEN',flush=True)
output={'engine':'LanguageTool','version':'6.6','catalogEntries':len(catalog),'distinctPrimaryLanguages':len(primary),'verifiedRuleLanguageCount':len(results),'verifiedExamples':results,'catalog':catalog,'limits':'Rule examples establish execution, not equal quality or complete grammar coverage. Native Apple grammar languages are not inferred from spell dictionaries.'}
pathlib.Path(a.output).write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
if len(results)<20: raise SystemExit('Fewer than20 primary language rule examples proved')
