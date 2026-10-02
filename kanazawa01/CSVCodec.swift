import Foundation

enum CSVCodec {
    static let header = ["ID", "通番", "実施回", "レベル", "分類", "問題番号", "問", "選択肢1", "選択肢2", "選択肢3", "選択肢4", "答え", "解説", "実施日", "備考"]
    static let maximumBytes = 20 * 1024 * 1024

    static func encode(_ questions: [Mondai]) -> String {
        ([header] + questions.map(\.csvFields)).map { row in
            row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    static func decode(_ source: String) throws -> [Mondai] {
        guard source.utf8.count <= maximumBytes else { throw AppError(message: "CSVは20MB以下にしてください。") }
        let rows = try parse(source)
        guard let first = rows.first, first.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) == header else {
            throw AppError(message: "CSVの見出しが異なります。IDから備考までの15列が必要です。")
        }
        guard rows.count > 1 else { throw AppError(message: "CSVに問題がありません。") }
        return try rows.dropFirst().enumerated().map { offset, fields in
            let record = offset + 2
            guard fields.count == 15 else {
                throw AppError(message: "CSVの\(record)レコード目は\(fields.count)列です。15列必要です。")
            }
            let trimmed = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let id = Int(trimmed[0]), id >= 0, let seq = Int(trimmed[1]), seq >= 0,
                  let number = Int(trimmed[5]), number > 0 else {
                throw AppError(message: "CSVの\(record)レコード目のID・通番・問題番号が不正です。")
            }
            let question = Mondai(id: id, seq: seq, kai: fields[2], level: fields[3], category: fields[4],
                                  number: number, question: fields[6], sel1: fields[7], sel2: fields[8],
                                  sel3: fields[9], sel4: fields[10], answer: fields[11], description: fields[12],
                                  hiduke: fields[13], bikou: fields[14])
            do { try question.validate() }
            catch { throw AppError(message: "CSVの\(record)レコード目：\(error.localizedDescription)") }
            return question
        }
    }

    /// カンマ、引用符の二重化、引用符内改行、CRLF、BOMを扱う。
    private static func parse(_ source: String) throws -> [[String]] {
        var normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let chars = Array(normalized)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var index = 0
        func malformed() -> AppError { AppError(message: "CSVの\(rows.count + 1)レコード目の引用符が不正です。") }
        func finishRow() {
            row.append(field)
            // 空の物理行だけを除外。15列の空レコードは検証でエラーにする。
            if row.count > 1 || closedQuote || !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(row)
            }
            row = []; field = ""; closedQuote = false
        }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        field.append("\""); index += 1
                    } else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else {
                switch char {
                case ",": row.append(field); field = ""; closedQuote = false
                case "\n": finishRow()
                case "\"":
                    guard field.isEmpty, !closedQuote else { throw malformed() }
                    quoted = true
                default:
                    guard !closedQuote else { throw malformed() }
                    field.append(char)
                }
            }
            index += 1
        }
        guard !quoted else { throw malformed() }
        if !row.isEmpty || !field.isEmpty || closedQuote { finishRow() }
        return rows
    }
}
