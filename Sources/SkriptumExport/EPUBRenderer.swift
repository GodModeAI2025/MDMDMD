import Foundation

struct EPUBRenderer {
    let document: SemanticDocument
    let profile: ExportProfile
    func archive() throws -> Data {
        var renderer = HTMLRenderer(document: document, profile: profile, packaged: true)
        let content = renderer.html()
        let id = "urn:uuid:\(UUID().uuidString)"
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; let modified = formatter.string(from: Date())
        let toc = renderer.navigation.isEmpty ? [("", document.input.title)] : renderer.navigation
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(escape(document.input.language))" xml:lang="\(escape(document.input.language))"><head><title>Contents</title></head><body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>\(toc.map { "<li><a href=\"content.xhtml\($0.0.isEmpty ? "" : "#" + $0.0)\">\(escape($0.1))</a></li>" }.joined())</ol></nav></body></html>
        """
        let assetManifest = document.imagePaths.enumerated().map { index, path in "<item id=\"image\(index + 1)\" href=\"\(renderer.imageName(path))\" media-type=\"\(escape(document.input.assets[path]!.mediaType))\" />" }.joined()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">\(id)</dc:identifier><dc:title>\(escape(document.input.title))</dc:title><dc:language>\(escape(document.input.language))</dc:language><dc:creator>\(escape(document.input.author))</dc:creator><meta property="dcterms:modified">\(modified)</meta></metadata><manifest><item id="content" href="content.xhtml" media-type="application/xhtml+xml" /><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" /><item id="css" href="style.css" media-type="text/css" />\(assetManifest)</manifest><spine><itemref idref="content" /></spine></package>
        """
        let container = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\" /></rootfiles></container>"
        var entries: [StoredZIP.Entry] = [.init(name: "mimetype", data: Data("application/epub+zip".utf8)), .init(name: "META-INF/container.xml", data: Data(container.utf8)), .init(name: "EPUB/package.opf", data: Data(opf.utf8)), .init(name: "EPUB/content.xhtml", data: Data(content.utf8)), .init(name: "EPUB/nav.xhtml", data: Data(nav.utf8)), .init(name: "EPUB/style.css", data: Data(themeCSS(document.input.theme ?? .preset(for: profile)).utf8))]
        for path in document.imagePaths { entries.append(.init(name: "EPUB/" + renderer.imageName(path), data: document.input.assets[path]!.data)) }
        return try StoredZIP.archive(entries)
    }
}
