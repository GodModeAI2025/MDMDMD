#!/usr/bin/env python3
import hashlib, io, json, logging, os, subprocess
from pathlib import Path
from pypdf import PdfReader
from PIL import Image

root = Path(os.environ['SCRIPTUM_PDF_LANGUAGE_QA_OUTPUT'])
poppler = os.environ['SCRIPTUM_PDFTOPPM']
results = []
for tag in ('de-DE', 'en-GB', 'zh-Hant-TW'):
    captures = io.StringIO(); handler = logging.StreamHandler(captures)
    logger = logging.getLogger('pypdf'); logger.addHandler(handler)
    try:
        before = PdfReader(root/(tag+'-before.pdf'), strict=True)
        after = PdfReader(root/(tag+'-after.pdf'), strict=True)
        assert before.trailer['/Root'].get('/Lang') is None
        assert after.trailer['/Root']['/Lang'] == tag
        assert after.trailer['/Root']['/StructTreeRoot']
        assert '/Prev' in after.trailer
        assert len(before.pages) == len(after.pages)
        languages = []
        def walk(node):
            if hasattr(node, 'get_object'): node = node.get_object()
            if isinstance(node, dict):
                if '/Lang' in node: languages.append(str(node['/Lang']))
                if '/K' in node: walk(node['/K'])
            elif isinstance(node, list):
                for child in node: walk(child)
        walk(after.trailer['/Root']['/StructTreeRoot'])
        assert tag in languages, languages
        text = ''
        for old, new in zip(before.pages, after.pages):
            assert old.extract_text() == new.extract_text()
            assert old.get_contents().get_data() == new.get_contents().get_data()
            assert list(old.mediabox) == list(new.mediabox)
            text += new.extract_text()
        assert text.count('🦊') == 1
        for variant in ('before', 'after'):
            subprocess.run([poppler, '-scale-to', '1100', '-png', str(root/(tag+'-'+variant+'.pdf')), str(root/(tag+'-'+variant))], check=True, capture_output=True, timeout=30)
        comparisons = []
        for page in range(1, len(after.pages)+1):
            old = root/(tag+'-before-'+str(page)+'.png'); new = root/(tag+'-after-'+str(page)+'.png')
            a = Image.open(old).convert('RGB'); b = Image.open(new).convert('RGB')
            assert a.size == b.size and a.tobytes() == b.tobytes()
            comparisons.append(dict(page=page, size=list(a.size), raster_sha256=hashlib.sha256(a.tobytes()).hexdigest(), pixel_equal=True))
        assert not captures.getvalue(), captures.getvalue()
        results.append(dict(tag=tag, pages=len(after.pages), structure_languages=languages, text_equal=True, content_streams_equal=True, fox_count=text.count('🦊'), reader_warnings=captures.getvalue(), rasters=comparisons))
    finally: logger.removeHandler(handler)
Path(__file__).with_name('INDEPENDENT_READER_RESULT.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
