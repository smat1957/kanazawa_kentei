import SwiftUI
import UniformTypeIdentifiers

enum QuestionFileFormat: String {
    case json = "JSON"
    case csv = "CSV"

    var contentType: UTType { self == .json ? .json : .commaSeparatedText }
    var fileExtension: String { self == .json ? "json" : "csv" }
}

struct QuestionFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw AppError(message: "ファイルの内容を読み込めませんでした。")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum QuestionFileCodec {
    private struct JSONArchive: Codable {
        let format: String
        let version: Int
        let questions: [Mondai]
    }

    static func read(_ url: URL) throws -> [Mondai] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > CSVCodec.maximumBytes {
            throw AppError(message: "インポートするファイルは20MB以下にしてください。")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= CSVCodec.maximumBytes else {
            throw AppError(message: "インポートするファイルは20MB以下にしてください。")
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw AppError(message: "UTF-8形式のJSONまたはCSVファイルを選んでください。")
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let first = text.first(where: { !$0.isWhitespace })
        guard first != nil else { throw AppError(message: "ファイルが空です。") }
        // JSONらしい内容が壊れていても、CSVとして読み直して隠蔽しない。
        if first == "{" || first == "[" {
            return try decodeJSON(Data(text.utf8))
        }
        return try CSVCodec.decode(text)
    }

    static func encode(_ questions: [Mondai], format: QuestionFileFormat) throws -> Data {
        let data: Data
        switch format {
        case .csv:
            data = Data(CSVCodec.encode(questions).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(JSONArchive(format: "Kanazawa", version: 1, questions: questions))
        }
        guard data.count <= CSVCodec.maximumBytes else {
            throw AppError(message: "書出データが20MBを超えています。インポート可能な上限を超えるため書き出せません。")
        }
        return data
    }

    private static func decodeJSON(_ data: Data) throws -> [Mondai] {
        let questions: [Mondai]
        do {
            let archive = try JSONDecoder().decode(JSONArchive.self, from: data)
            guard archive.format == "Kanazawa", archive.version == 1 else {
                throw AppError(message: "このJSONの形式またはバージョンには対応していません。")
            }
            questions = archive.questions
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError(message: "JSONの構造が不正です。Kanazawaで書き出したJSON形式が必要です。\n\(error.localizedDescription)")
        }
        guard !questions.isEmpty else { throw AppError(message: "JSONに問題がありません。") }
        for (index, question) in questions.enumerated() {
            guard question.id >= 0 else { throw AppError(message: "JSONの\(index + 1)件目のIDが不正です。") }
            do { try question.validate() }
            catch { throw AppError(message: "JSONの\(index + 1)件目：\(error.localizedDescription)") }
        }
        return questions
    }
}
