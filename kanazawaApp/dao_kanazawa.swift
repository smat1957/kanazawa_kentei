//
//  dao.swift
//  kanazawa
//
//  Created by 的池秋成 on 2025/05/14.
//

import SwiftUI
import SQLite3
import SwiftData

//
// https://swappli.com/fileimporter1/
// https://swiftwithmajid.com/2023/05/10/file-importing-and-exporting-in-swiftui/
//
import UniformTypeIdentifiers

struct SmpFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

/// SQLite3
/// https://qiita.com/SolaRayLino/items/06704b4709c700f3c3fa
class SQLite3 {

    /// Connection
    private var db: OpaquePointer?

    /// Statement
    private var statement: OpaquePointer?

    /// データベースを開く
    /// - Parameter path: ファイルパス
    /// - Returns: 実行結果
    @discardableResult
    func open(path: String) -> Int {
        let ret = sqlite3_open_v2(path, &self.db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)

        if ret != SQLITE_OK {
            print("error sqlite3_open_v2: code=\(ret)")
        }

        return Int(ret)
    }

    /// ステートメントを生成しないでSQLを実行
    /// - Parameter sql: SQL
    /// - Returns: 実行結果
    @discardableResult
    func exec(_ sql: String) -> Int {
        let ret = sqlite3_exec(self.db, sql, nil, nil, nil)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_exec: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// ステートメントの生成
    /// - Parameter sql: SQL
    /// - Returns: 実行結果
    @discardableResult
    func prepare(_ sql: String) -> Int {
        let ret = sqlite3_prepare_v2(self.db, sql, -1, &self.statement, nil)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_prepare_v2: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// 作成されたステートメントにInt型パラメーターを生成
    /// - Parameters:
    ///   - index: インデックス
    ///   - value: 値
    /// - Returns: 実行結果
    @discardableResult
    func bindInt(index: Int, value: Int) -> Int {
        let ret = sqlite3_bind_int(self.statement, Int32(index), Int32(value))

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_bind_int: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// 作成されたステートメントにString型(UTF-8)パラメーターを生成
    /// - Parameters:
    ///   - index: インデックス
    ///   - value: 値
    /// - Returns: 実行結果
    @discardableResult
    func bindText(index: Int, value: String) -> Int {
        let ret = sqlite3_bind_text(self.statement, Int32(index), (value as NSString).utf8String, -1, nil)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_bind_text: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// ステートメントの実行（SELECTの場合は行の取得）
    /// - Returns: 実行結果
    @discardableResult
    func step() -> Int {
        let ret = sqlite3_step(self.statement)

        if ret != SQLITE_ROW && ret != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_step: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// ステートメントのリセット
    /// - Returns: 実行結果
    @discardableResult
    func resetStatement() -> Int {
        let ret = sqlite3_reset(self.statement)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_reset: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// ステートメントの破棄
    /// - Returns: 実行結果
    @discardableResult
    func finalizeStatement() -> Int {
        let ret = sqlite3_finalize(self.statement)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_finalize: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// SELECTしたステートメントからInt値を取得
    /// - Parameter index: カラムインデックス(0から)
    /// - Returns: Int値
    func columnInt(index: Int) -> Int {
        return Int(sqlite3_column_int(self.statement, Int32(index)))
    }

    /// SELECTしたステートメントからString値を取得
    /// - Parameter index: カラムインデックス(0から)
    /// - Returns: String値
    func columnText(index: Int) -> String {
        return String(cString: sqlite3_column_text(self.statement, Int32(index)))
    }

    /// データベースを閉じる
    /// - Returns: 実行結果
    @discardableResult
    func close() -> Int {
        let ret = sqlite3_close_v2(self.db)

        if ret != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(self.db)!)
            print("error sqlite3_close_v2: code=\(ret), errmsg=\(msg)")
        }

        return Int(ret)
    }

    /// テーブル存在チェック
    /// - Parameters:
    ///   - sqlite3: SQLite3
    ///   - table: テーブル名
    func existsTable(_ tableName: String) -> Bool {
        self.prepare("SELECT COUNT(*) AS CNT FROM sqlite_master WHERE type = ? and name = ?")
        defer { self.finalizeStatement() }

        self.bindText(index: 1, value: "table")
        self.bindText(index: 2, value: tableName)

        if self.step() == SQLITE_ROW {
            if self.columnInt(index: 0) > 0 {
                return true
            }
        }

        return false
    }
}

struct Mondai {
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
}

nonisolated(unsafe) var mondai = [Mondai]()

class DAO:SQLite3{
    let table_name:String = "kanazawa"
    func initial(){
        let rootDirectory = NSHomeDirectory() + "/Documents"
        open(path: rootDirectory+"/"+table_name+"_sqlite3")
        //drop_table()
        //create_table()
        print("dao!->",rootDirectory+"/"+table_name+"_sqlite3")
    }
    func drop_table(){
        exec("""
    DROP TABLE \(table_name)
    """)
    }
    func create_table(){
        exec("""
    CREATE TABLE \(table_name) (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        seq INTEGER,
        kai TEXT,
        level TEXT,
        category TEXT,
        number INTEGER,
        question TEXT,
        sel1 TEXT,
        sel2 TEXT,
        sel3 TEXT,
        sel4 TEXT,
        answer TEXT,
        description TEXT,
        hiduke TEXT,
        bikou TEXT
    )
    """)
    }
    func delete(id:Int){
        prepare("DELETE FROM \(table_name) WHERE id=?")
        bindInt(index: 1, value: id)
        if step() != SQLITE_DONE {
            print("error: DELETE")
        }
        resetStatement()
    }
    
    func insert_fromcsv(data:[String]){
        prepare("INSERT INTO \(table_name)(seq,kai,level,category,number,question,sel1,sel2,sel3,sel4,answer,description,hiduke,bikou) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        bindInt(index: 1, value: Int(data[0])!-1)
        for i in 1..<14{
            if (i==4){
                bindInt(index: i+1, value: Int(data[i+1])!-1)
            }
            bindText(index: i+1, value: String(data[i+1]))
            //print("INSERT: ",i+1,data[i+1])
        }
        if step() != SQLITE_DONE {
            print("error: INSERT csv")
        }
        resetStatement()
    }
    
    func insert(data:[String]){
        prepare("INSERT INTO \(table_name)(seq,kai,level,category,number,question,sel1,sel2,sel3,sel4,answer,description,hiduke,bikou) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        bindInt(index: 1, value: Int(data[0])!-1)
        for i in 1..<14{
            if (i==4){
                bindInt(index: i+1, value: Int(data[i])!-1)
            }
            bindText(index: i+1, value: String(data[i]))
            //print("INSERT: ",i+1,data[i+1])
        }
        if step() != SQLITE_DONE {
            print("error: INSERT")
        }
        resetStatement()
    }
    func update(data:[String], id:Int){
        prepare("UPDATE \(table_name) SET seq=?,kai=?,level=?,category=?,number=?,question=?,sel1=?,sel2=?,sel3=?,sel4=?,answer=?,description=?,hiduke=?,bikou=?  WHERE id=?")
        bindInt(index: 1, value: Int(data[0])!-1)
        for i in 1..<14{
            if (i==4){
                bindInt(index: i+1, value: Int(data[i])!-1)
            }
            bindText(index: i+1, value: String(data[i]))
        }
        bindInt(index: 15, value: id)
        if step() != SQLITE_DONE {
            print("error: UPDATE")
        }
        resetStatement()
    }
    
    func append_mondai(){
        mondai.removeAll()
        while step() == SQLITE_ROW {
            let id = columnInt(index: 0)
            let seq = columnInt(index: 1)
            let kai = columnText(index: 2)
            let level = columnText(index: 3)
            let category = columnText(index: 4)
            let number = columnInt(index: 5)
            let question = columnText(index: 6)
            let sel1 = columnText(index: 7)
            let sel2 = columnText(index: 8)
            let sel3 = columnText(index: 9)
            let sel4 = columnText(index: 10)
            let answer = columnText(index: 11)
            let description = columnText(index: 12)
            let hiduke = columnText(index: 13)
            let bikou = columnText(index: 14)
            mondai.append(Mondai(id:id, seq:seq, kai:kai, level:level, category:category, number:number, question:question, sel1:sel1, sel2:sel2, sel3:sel3, sel4:sel4, answer:answer, description:description, hiduke:hiduke, bikou:bikou))
            //print("IntField:\(id),\(seq), TextField:\(mondai)")
        }
    }
    func distinct(field_name: String) -> [String]{
        let sql = "SELECT DISTINCT \(field_name) FROM \(table_name) ORDER BY \(field_name) ASC"
        prepare(sql)
        var list = [String]()
        while step() == SQLITE_ROW {
            list.append(columnText(index: 0))
        }
        if step() != SQLITE_DONE {
            print("error: SELECT: distinct")
        }
        resetStatement()
        return list
    }
    func select_all(){
        prepare("SELECT * FROM \(table_name) ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: All")
        }
        resetStatement()
    }
    
    func select_kai(kai:String){
        prepare("SELECT * FROM \(table_name) WHERE kai = ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: kai)
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: Kai")
        }
        resetStatement()
    }

    func select_level(level:String){
        prepare("SELECT * FROM \(table_name) WHERE level = ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: level)
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: Level")
        }
        resetStatement()
    }

    func select_category(category:String){
        prepare("SELECT * FROM \(table_name) WHERE category LIKE ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: category+"%")
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: Category")
        }
        resetStatement()
    }

    func select_kai_level(kai:String, level:String){
        prepare("SELECT * FROM \(table_name) WHERE kai = ? AND level = ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: kai)
        bindText(index: 2, value: level)
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: Kai, Level")
        }
        resetStatement()
    }
    
    func select_kai_level_category(kai:String, level:String, category:String){
        prepare("SELECT * FROM \(table_name) WHERE kai = ? AND level = ? AND category LIKE ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: kai)
        bindText(index: 2, value: level)
        bindText(index: 3, value: category+"%")
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: Kai, Level, Category")
        }
        resetStatement()
    }

    func select_keyword(keyword:String){
        prepare("SELECT * FROM \(table_name) WHERE category LIKE ? OR question LIKE ? OR sel1 LIKE ? OR sel2 LIKE ? OR sel3 LIKE ? OR sel4 LIKE ? OR  description LIKE ? ORDER BY kai ASC, level ASC, number ASC, category ASC, seq ASC")
        bindText(index: 1, value: "%"+keyword+"%")
        bindText(index: 2, value: "%"+keyword+"%")
        bindText(index: 3, value: "%"+keyword+"%")
        bindText(index: 4, value: "%"+keyword+"%")
        bindText(index: 5, value: "%"+keyword+"%")
        bindText(index: 6, value: "%"+keyword+"%")
        bindText(index: 7, value: "%"+keyword+"%")
        append_mondai()
        if step() != SQLITE_DONE {
            print("error: SELECT: KeyWord")
        }
        resetStatement()
    }
}

extension String {
    var length: Int {
        return count
    }

    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, length) ..< length]
    }

    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
}

class myCSV{
    var fname = "KanazawaData"
    init(fname: String = "KanazawaData"){
        self.fname = fname
    }
    func getFName() -> String {
        return self.fname+".csv"
    }
    
    func CSVDataGen() -> String {
        // heading of CSV file.
        let heading = "ID,通番,実施回,レベル,分類,問題番号,問,選択肢1,選択肢2,選択肢3,選択肢4,答え,解説,実施日,備考 \n"
        // file rows
        let rows = mondai.map {
            "\($0.id),\($0.seq),\"\($0.kai)\",\($0.level),\"\($0.category)\",\"\($0.number)\",\"\($0.question)\",\"\($0.sel1)\",\"\($0.sel2)\",\"\($0.sel3)\",\"\($0.sel4)\",\"\($0.answer)\",\($0.description),\($0.hiduke),\($0.bikou)"
        }
        // rows to string data
        let stringData = heading + rows.joined(separator: "\n")
        return stringData
    }
    
    func generateCSV() -> URL {
        var fileURL: URL!
        let stringData = CSVDataGen()
        do {
            let path = try FileManager.default.url(for: .documentDirectory,
                                                   in: .allDomainsMask,
                                                   appropriateFor: nil,
                                                   create: false)
            fileURL = path.appendingPathComponent(self.fname+".csv")
            // append string data to file
            try stringData.write(to: fileURL, atomically: true , encoding: .utf8)
            print(fileURL!)
        } catch {
            print("error : generating csv file")
        }
        return fileURL
    }
    /* Generate csv */
    func fileContents(file: URL) -> String{
        // アクセス権取得
        let gotAccess = file.startAccessingSecurityScopedResource()
        if !gotAccess { return ""}
        // ファイルの内容を取得する
        //let filename = file.lastPathComponent
        //let directoryURL = file.deletingLastPathComponent()
        //let folder = URL(fileURLWithPath: directoryURL.path)
        //let filen = folder.appendingPathComponent(filename)
        //print("file://"+directoryURL.path+"/"+filename)
        var text: String = ""
        do {
            text = try String(contentsOf: file, encoding: String.Encoding.utf8)
        } catch {
            print(error.localizedDescription)
        }
        // アクセス権解放
        file.stopAccessingSecurityScopedResource()
        return text
    }
    
    func reshape(url: URL) -> [[String]]{
        var outdata: [[String]] = [[]]
        var csvdata: [String] = []
        var str: String = ""
        var flag: Bool = false
        let textString: String = fileContents(file: url)
        let lineChange = textString.replacingOccurrences(of: "\r", with: "\n")
        var lineArray: [String] = lineChange.components(separatedBy: "\n")
        if lineArray.last!.isEmpty{
            lineArray.removeLast()
        }
        for line in lineArray {
            var CR: Bool = false
            if flag {
                CR = true
            }
            let dataArray: [String] = line.components(separatedBy: ",")
            if(dataArray[0]=="ID"){continue}
            for data in dataArray{
                var CM: Bool = false
                if flag {
                    CM = true
                }
                if data=="\"" {
                    if flag {
                        csvdata.append(str.replacingOccurrences(of:"\"", with:""))
                        flag = false
                        CM = false
                        CR = false
                    }else{
                        flag=true
                    }
                } else if (!data.hasPrefix("\"")&&(!data.hasSuffix("\""))){
                    if flag {
                        var sep:String = ""
                        if CM {
                            sep = ", "
                        }
                        if CR {
                            sep = "\n"
                        }
                        if str.isEmpty {
                            if CM||CR {
                                str = sep + data
                            }else{
                                str = data
                            }
                            
                        }else{
                            if CM||CR {
                                str = str + sep + data
                            }else{
                                str += data
                            }
                        }
                        if CM {CM=false}
                        if CR {CR=false}
                    }else{
                        csvdata.append(data.replacingOccurrences(of:"\"", with:""))
                        CM = false
                        CR = false
                    }
                }else if (data.hasPrefix("\"")&&(data.hasSuffix("\""))){
                    csvdata.append(data.replacingOccurrences(of:"\"", with:""))
                    CM = false
                    CR = false
                }else if (data.hasPrefix("\"")&&(!data.hasSuffix("\""))){
                    str = data
                    flag = true
                }else if ((!data.hasPrefix("\""))&&(data.hasSuffix("\""))){
                    if str.isEmpty {
                        str = data
                    }else{
                        var sep:String = ""
                        if CM {
                            sep = ", "
                        }
                        if CR {
                            sep = "\n"
                        }
                        if CR||CM {
                            str = str + sep + data
                        }else{
                            str += data
                        }
                        if CM {CM=false}
                        if CR {CR=false}
                    }
                    csvdata.append(str.replacingOccurrences(of:"\"", with:""))
                    flag = false
                    CM = false
                    CR = false
                }
                if 16==csvdata.count{
                    if csvdata[0]==""{
                        csvdata.removeFirst()
                    }
                    outdata.append(csvdata)
                    csvdata.removeAll()
                }
            }
        }
        return outdata
    }

}

extension UIApplication {
    func closeKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
