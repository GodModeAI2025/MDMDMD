import Testing
@testable import SkriptumBlocks
@Test func exactUnicodeCRLFReplacement() throws {
 let source = "  | 名字  | Wert |\r\n  | :--- | ---: |\r\n  | Ä👩🏽‍💻 | `a\\|b` |\r\n\r\n"
 let table = try MarkdownTable(source)
 #expect(table.cells == [["名字", "Wert"], ["Ä👩🏽‍💻", "`a\\|b`"]])
 #expect(try table.replacingCell(row: 1, column: 0, markdown: "Neu🦉") == "  | 名字  | Wert |\r\n  | :--- | ---: |\r\n  | Neu🦉 | `a\\|b` |\r\n\r\n")
 #expect(try table.replacingCell(row: 1, column: 0, markdown: "Ä👩🏽‍💻") == source)
}
@Test func rowsAndColumns() throws {
 let source = "A | B\n--- | :---:\nx | y"
 let table = try MarkdownTable(source)
 #expect(try table.insertingRow(at: 1, cells: ["z", "w"]) == "A | B\n--- | :---:\nx | y\nz | w")
 #expect(try table.removingRow(at: 0) == "A | B\n--- | :---:")
 let added = try table.insertingColumn(at: 1, heading: "C", cells: ["q"])
 #expect(try MarkdownTable(added).cells == [["A", "C", "B"], ["x", "q", "y"]])
 #expect(try MarkdownTable(added).removingColumn(at: 1) == source)
}
@Test(arguments: ["", "text", "| A | B |\n| --- |\n", "| A |\n| --- |\n| x | y |", "| A |\n| - |", "| `a|b` | C |\n| --- | --- |", "| A |\n| --- |\n\nother", "    | A |\n    | --- |"])
func malformedRejected(_ source: String) { #expect(throws: TableEditingError.malformed) { try MarkdownTable(source) } }
@Test func mutationGuards() throws {
 let table = try MarkdownTable("| A |\n| --- |\n| x |");
 #expect(throws: TableEditingError.invalidCell) { try table.replacingCell(row: 1, column: 0, markdown: "a|b") }
 #expect(throws: TableEditingError.invalidCell) { try table.replacingCell(row: 1, column: 0, markdown: "a\nb") }
 #expect(throws: TableEditingError.lastColumn) { try table.removingColumn(at: 0) }
 #expect(throws: TableEditingError.outOfBounds) { try table.removingRow(at: 1) }
}
@Test func escapedPipesBacktickRunsAndEmptyCells() throws {
 let source = "| ``a`\\|b`` | empty |\n| --- | --- |\n| a\\|b |  |\n"
 let table = try MarkdownTable(source)
 #expect(table.cells == [["``a`\\|b``", "empty"], ["a\\|b", ""]])
 #expect(try table.replacingCell(row: 1, column: 1, markdown: "`x\\|y`") == "| ``a`\\|b`` | empty |\n| --- | --- |\n| a\\|b | `x\\|y` |\n")
}
@Test func structuralCRLFAndTailPreservation() throws {
 let source = " | A | B |\r\n | --- | --- |\r\n | x | y |\r\n \r\n"
 let table = try MarkdownTable(source)
 let inserted = try table.insertingRow(at: 0, cells: ["z", "w"])
 #expect(inserted == " | A | B |\r\n | --- | --- |\r\n | z | w |\r\n | x | y |\r\n \r\n")
 #expect(try MarkdownTable(inserted).removingRow(at: 0) == source)
 let column = try table.insertingColumn(at: 2, heading: "C", cells: ["v"])
 #expect(column == " | A | B | C |\r\n | --- | --- | --- |\r\n | x | y | v |\r\n \r\n")
 #expect(try MarkdownTable(column).removingColumn(at: 2) == source)
}

@Test func removingToSingleColumnAddsOnlyRequiredOuterPipes() throws {
    let source = "  A | B\r\n  :--- | ---:\r\n  😀 e\u{301} | y\r\n \r\n"
    let output = try MarkdownTable(source).removingColumn(at: 1)
    #expect(output == "  |A |\r\n  |:--- |\r\n  |😀 e\u{301} |\r\n \r\n")
    #expect(try MarkdownTable(output).cells == [["A"], ["😀 e\u{301}"]])
    #expect(throws: TableEditingError.lastColumn) { try MarkdownTable(output).removingColumn(at: 0) }
}
@Test func normalizationEditIsNotDiscarded() throws {
    let source = "| H |\n| --- |\n| e\u{301} |"
    let output = try MarkdownTable(source).replacingCell(row: 1,column: 0,markdown: "é")
    #expect(output.utf8.elementsEqual("| H |\n| --- |\n| é |".utf8))
    #expect(!output.utf8.elementsEqual(source.utf8))
}
@Test func headerBlockSyntaxRetainsTableSemantics() throws {
    let source = "a | b\n--- | ---\nx | y"
    let output = try MarkdownTable(source).replacingCell(row: 0,column: 0,markdown: "# H")
    #expect(output == "|# H | b|\n|--- | ---|\n|x | y|")
    #expect(try MarkdownTable(output).cells[0] == ["# H", "b"])
    #expect(throws: TableEditingError.malformed) { try MarkdownTable("# H | b\n--- | ---\nx | y") }
}
@Test(arguments: ["# H", "- item", "> quote", "```", "<div>", "---"])
func editedHeaderRemainsSemanticTable(_ header: String) throws {
    let source = "a | b\r\n--- | ---\r\nx | y\r\n\r\n"
    let output = try MarkdownTable(source).replacingCell(row: 0,column: 0,markdown: header)
    let parsed = try MarkdownTable(output)
    #expect(parsed.cells == [[header, "b"], ["x", "y"]])
    #expect(output.hasSuffix("\r\n\r\n"))
}
