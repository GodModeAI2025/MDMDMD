import Foundation
import SkriptumExport
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let source = "# Kapitel 🦊\n\nCafé e\u{301} und **Fett** mit Quelle [W3C](https://www.w3.org/).\n\n| Name | Wert |\n| --- | ---: |\n| Grüße | 42 |\n\nText[^n].\n\n[^n]: Anmerkung.\n"
for (name, author) in [("no-author", ""), ("blank-author", " \t\n"), ("named-author", "Dr. Café e\u{301} & <Autor> 🦊")] {
 let result = try ExportEngine.export(ExportInput(title: "Prüfbuch 🦊", markdown: source, author: author), format: .epub)
 try result.data.write(to: out.appendingPathComponent(name + ".epub"))
}
var chapters: [ExportInput] = []
for i in 1...24 {
 let paragraph = "Absatz \(i): Café e\u{301} 🦊 — **Fett**, *kursiv*, [Quelle](https://www.w3.org/).\n\n"
 chapters.append(ExportInput(title: "Kapitel \(i)", markdown: "# Gliederung \(i)\n\n" + String(repeating: paragraph, count: 60) + "| Name | Wert |\n| --- | ---: |\n| Grüße | \(i) |\n\nText[^n].\n\n[^n]: Fußnote \(i).\n"))
}
for profile in ExportProfile.allCases {
 let result = try ExportEngine.exportManuscript(title: "Langes Prüfbuch", chapters: chapters, format: .epub, profile: profile)
 try result.data.write(to: out.appendingPathComponent("manuscript-" + profile.rawValue + ".epub"))
}
print("Generated six EPUB fixtures from the actual ExportEngine.")
