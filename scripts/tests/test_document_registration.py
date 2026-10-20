import plistlib
from pathlib import Path
import unittest


class ExternalDocumentRegistration(unittest.TestCase):
    def test_both_apps_advertise_editable_markdown_and_plain_text(self):
        root = Path(__file__).resolve().parents[2]
        for name in ('Info.plist', 'Info-Mac.plist'):
            with self.subTest(platform=name):
                info = plistlib.loads((root / 'Config' / name).read_bytes())
                editors = set()
                for entry in info.get('CFBundleDocumentTypes', []):
                    if entry.get('CFBundleTypeRole') == 'Editor':
                        editors.update(entry.get('LSItemContentTypes', []))
                self.assertTrue({'net.daringfireball.markdown', 'public.plain-text'} <= editors)
                markdown = next((item for item in info.get('UTImportedTypeDeclarations', [])
                                 if item.get('UTTypeIdentifier') == 'net.daringfireball.markdown'), {})
                self.assertIn('public.plain-text', markdown.get('UTTypeConformsTo', []))
                self.assertTrue({'md', 'markdown'} <= set(markdown.get('UTTypeTagSpecification', {}).get('public.filename-extension', [])))

    def test_ios_accepts_open_in_place(self):
        root = Path(__file__).resolve().parents[2]
        info = plistlib.loads((root / 'Config/Info.plist').read_bytes())
        self.assertIs(info.get('LSSupportsOpeningDocumentsInPlace'), True)


if __name__ == '__main__':
    unittest.main()
