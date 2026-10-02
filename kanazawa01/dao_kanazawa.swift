import Foundation
import SQLite3

struct AppError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

struct Mondai: Identifiable, Sendable, Codable {
    var id: Int
    var seq: Int
    var kai: String
    var level: String
    var category: String
    var number: Int
    var question: String
    var sel1: String
    var sel2: String
    var sel3: String
    var sel4: String
    var answer: String
    var description: String
    var hiduke: String
    var bikou: String

    var choices: [String] { [sel1, sel2, sel3, sel4] }
    var csvFields: [String] {
        [String(id), String(seq), kai, level, category, String(number), question,
         sel1, sel2, sel3, sel4, answer, description, hiduke, bikou]
    }

    func validate() throws {
        guard csvFields.allSatisfy({ !$0.contains("\0") }) else {
            throw AppError(message: "文字列に使用できないNULL文字が含まれています。")
        }
        guard seq >= 0, number > 0 else {
            throw AppError(message: "通番は0以上、問題番号は1以上の整数にしてください。")
        }
        guard !kai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !level.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              choices.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AppError(message: "実施回・級・問題文・4つの選択肢・答えは必須です。")
        }
    }
}

/// 既存のDocuments/kanazawa_sqlite3とテーブル形式を引き継ぐ。
/// この接続はDataManagerの専用キューだけで使用する。
final class DAO: @unchecked Sendable {
    private var db: OpaquePointer?
    private let columns = "id,seq,kai,level,category,number,question,sel1,sel2,sel3,sel4,answer,description,hiduke,bikou"

    deinit { if let db = db { sqlite3_close_v2(db) } }

    private func failure(_ operation: String) -> AppError {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "DB未接続"
        return AppError(message: "\(operation)に失敗しました。\n\(detail)")
    }

    func initialize() throws {
        if db != nil { return }
        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        let url = directory.appendingPathComponent("kanazawa_sqlite3")
        var connection: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &connection,
                                  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let connection = connection else {
            let detail = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "DBを開けません"
            if let connection = connection { sqlite3_close_v2(connection) }
            throw AppError(message: "DBを開けませんでした。\n\(detail)")
        }
        db = connection
        do {
            guard sqlite3_busy_timeout(connection, 5000) == SQLITE_OK else { throw failure("DB設定") }
            try transaction {
                let hadTable = try tableExists("kanazawa")
                let hadMetadata = try tableExists("app_metadata")
                try execute("""
                    CREATE TABLE IF NOT EXISTS kanazawa (
                      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                      seq INTEGER, kai TEXT, level TEXT, category TEXT, number INTEGER,
                      question TEXT, sel1 TEXT, sel2 TEXT, sel3 TEXT, sel4 TEXT,
                      answer TEXT, description TEXT, hiduke TEXT, bikou TEXT)
                    """)
                // 明示した列で既存DBの互換性を確認する。壊れたDBは上書きしない。
                try withStatement("SELECT \(columns) FROM kanazawa LIMIT 0") { statement in
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("DB構造の確認") }
                }
                try execute("CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                // 旧版の空DBも初期化対象。初期化済みDBの意図的な空状態は保持する。
                let existingCount = try count()
                if !hadMetadata && (!hadTable || existingCount == 0) {
                    guard let url = Bundle.main.url(forResource: "InitialQuestions", withExtension: "csv")
                        ?? Bundle.main.url(forResource: "InitialQuestions", withExtension: "csv", subdirectory: "Resources") else {
                        throw AppError(message: "初期問題CSVがアプリに含まれていません。")
                    }
                    let questions = try CSVCodec.decode(String(contentsOf: url, encoding: .utf8))
                    for question in questions { try insert(question) }
                }
                try execute("INSERT OR IGNORE INTO app_metadata(key,value) VALUES ('schema_version','1')")
            }
        } catch {
            sqlite3_close_v2(connection)
            db = nil
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let db = db else { throw failure("DB操作") }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure("DB操作") }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let db = db else { throw failure("DB操作") }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let prepared = statement else {
            if let statement = statement { sqlite3_finalize(statement) }
            throw failure("SQLの準備")
        }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        // SQLITE_TRANSIENT: Swift側の文字列の寿命に依存せずSQLiteにコピーさせる。
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let code = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
        guard code == SQLITE_OK else { throw failure("文字列の設定") }
    }

    private func bind(_ value: Int, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
            throw failure("数値の設定")
        }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func tableExists(_ name: String) throws -> Bool {
        try withStatement("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?") { statement in
            try bind(name, to: statement, at: 1)
            let code = sqlite3_step(statement)
            guard code == SQLITE_ROW || code == SQLITE_DONE else { throw failure("テーブル確認") }
            return code == SQLITE_ROW
        }
    }

    private func count() throws -> Int {
        try withStatement("SELECT COUNT(*) FROM kanazawa") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { throw failure("件数確認") }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func selectAll() throws -> [Mondai] {
        try withStatement("SELECT \(columns) FROM kanazawa ORDER BY kai,level,number,category,seq,id") { statement in
            var result: [Mondai] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return result }
                guard code == SQLITE_ROW else { throw failure("問題の読込") }
                result.append(Mondai(
                    id: Int(sqlite3_column_int64(statement, 0)), seq: Int(sqlite3_column_int64(statement, 1)),
                    kai: text(statement, 2), level: text(statement, 3), category: text(statement, 4),
                    number: Int(sqlite3_column_int64(statement, 5)), question: text(statement, 6),
                    sel1: text(statement, 7), sel2: text(statement, 8), sel3: text(statement, 9), sel4: text(statement, 10),
                    answer: text(statement, 11), description: text(statement, 12), hiduke: text(statement, 13), bikou: text(statement, 14)))
            }
        }
    }

    private func bindFields(_ question: Mondai, to statement: OpaquePointer) throws {
        try question.validate()
        try bind(question.seq, to: statement, at: 1)
        for (offset, value) in question.csvFields.dropFirst(2).enumerated() {
            let index = Int32(offset + 2)
            if index == 5 { try bind(question.number, to: statement, at: index) }
            else { try bind(value, to: statement, at: index) }
        }
    }

    @discardableResult
    func insert(_ question: Mondai) throws -> Int {
        return try withStatement("INSERT INTO kanazawa(seq,kai,level,category,number,question,sel1,sel2,sel3,sel4,answer,description,hiduke,bikou) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)") { statement in
            try bindFields(question, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("問題の登録") }
            return Int(sqlite3_last_insert_rowid(db))
        }
    }

    func update(_ question: Mondai) throws {
        guard question.id > 0 else { throw AppError(message: "更新対象の問題がありません。") }
        try withStatement("UPDATE kanazawa SET seq=?,kai=?,level=?,category=?,number=?,question=?,sel1=?,sel2=?,sel3=?,sel4=?,answer=?,description=?,hiduke=?,bikou=? WHERE id=?") { statement in
            try bindFields(question, to: statement)
            try bind(question.id, to: statement, at: 15)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("問題の更新") }
            guard sqlite3_changes(db) == 1 else { throw AppError(message: "更新対象の問題が見つかりません。") }
        }
    }

    func delete(id: Int) throws {
        guard id > 0 else { throw AppError(message: "削除対象の問題がありません。") }
        try withStatement("DELETE FROM kanazawa WHERE id=?") { statement in
            try bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("問題の削除") }
            guard sqlite3_changes(db) == 1 else { throw AppError(message: "削除対象の問題が見つかりません。") }
        }
    }

    /// CSVのIDは他のDBと衝突するため、取込先で新しく割り当てる。
    func importQuestions(_ questions: [Mondai], replacing: Bool) throws {
        guard !questions.isEmpty else { throw AppError(message: "取込できる問題がありません。") }
        for question in questions { try question.validate() }
        try transaction {
            if replacing { try execute("DELETE FROM kanazawa") }
            for question in questions { try insert(question) }
        }
    }
}
