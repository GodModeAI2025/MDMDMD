from pathlib import Path
from pypdf import PdfReader
import logging,json,re
root=Path(__file__).parent/'fixtures'
class NoWarnings(logging.Handler):
    def emit(self,record): raise AssertionError(record.getMessage())
logging.getLogger('pypdf').addHandler(NoWarnings())
results=[]
for kind in ('image','mixed','table'):
    for mode in ('plain','tagged'):
        before=PdfReader(root/f'before-{kind}-{mode}.pdf',strict=True)
        after=PdfReader(root/f'after-{kind}-{mode}.pdf',strict=True)
        oldtexts=[p.extract_text() for p in before.pages]; texts=[p.extract_text() for p in after.pages]
        oldhead=next(i for i,t in enumerate(oldtexts) if 'TogetherMedia' in t)
        head=next(i for i,t in enumerate(texts) if 'TogetherMedia' in t)
        assert oldhead==0 and head==1
        assert re.sub(r'\s','', ''.join(oldtexts))==re.sub(r'\s','', ''.join(texts))
        if kind=='table':
            assert 'Column' in texts[head] and 'Row🦊' in re.sub(r'\s','',texts[head])
            assert ''.join(texts).count('🦊')==10
        else:
            annotations=[(i,a.get_object()) for i,p in enumerate(after.pages) for a in p.get('/Annots',[])]
            links=[(i,a) for i,a in annotations if '/A' in a and '/URI' in a['/A'] and a['/A']['/URI']=='https://example.com/figure']
            assert len(links)==1 and links[0][0]==head
            draws=[]
            for operands,op in after.pages[head].get_contents().operations:
                if op==b'Do':
                    obj=after.pages[head]['/Resources']['/XObject'][operands[0]]
                    if obj['/Subtype']=='/Image' and obj['/Width']==400 and obj['/Height']==600: draws.append(obj)
            assert len(draws)==1
            if kind=='mixed': assert 'AfterImage🦊' in re.sub(r'\s','', ''.join(texts))
        if mode=='tagged':
            roles=[]
            def walk(node):
                node=node.get_object() if hasattr(node,'get_object') else node
                if isinstance(node,list):
                    for x in node: walk(x)
                elif isinstance(node,dict):
                    if '/S' in node: roles.append(str(node['/S']))
                    if '/K' in node: walk(node['/K'])
            walk(after.trailer['/Root']['/StructTreeRoot']['/K'])
            assert roles.count('/H1')==1
            assert roles.count('/Figure' if kind!='table' else '/Table')==1
            if kind=='table':
                document=after.trailer['/Root']['/StructTreeRoot']['/K']
                table=next(x.get_object() for x in document['/K'] if x.get_object().get('/S')=='/Table')
                assert all(x.get_object().get('/S')=='/TR' for x in table['/K'])
        results.append({'kind':kind,'mode':mode,'pages':len(after.pages),'headingPageBefore':oldhead+1,'headingPageAfter':head+1,'samePageWithFollowingMedia':True,'sourceTextPreserved':True,'readerWarnings':0})
print(json.dumps(results,indent=2))
