import SwiftUI
import Combine

/// UI状態はメインスレッド、ファイル・DB処理は専用の直列キューで管理する。
@MainActor
final class DataManager: ObservableObject {
    @Published private(set) var allQuestions: [Mondai] = []
    @Published private(set) var questions: [Mondai] = []
    @Published private(set) var current = 0
    @Published private(set) var choices: [String] = []
    @Published var selectedChoice: Int?
    @Published var revealsAnswer = false
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false
    @Published var errorMessage: String?
    @Published var notice = ""
    @Published var searchKai = ""
    @Published var searchLevel = ""
    @Published var searchCategory = ""
    @Published var keyword = ""
    @Published private(set) var pendingImport: [Mondai] = []

    private var appliedKeyword = ""

    private let dao = DAO()
    private let workQueue = DispatchQueue(label: "jp.matoike.kanazawa.database", qos: .userInitiated)

    var question: Mondai? { questions.indices.contains(current) ? questions[current] : nil }
    var position: String { questions.isEmpty ? "0 / 0" : "\(current + 1) / \(questions.count)" }
    var kais: [String] { Array(Set(allQuestions.map(\.kai))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var levels: [String] {
        let values = Set(allQuestions.filter { $0.kai == searchKai }.map(\.level))
        let order = ["初": 0, "初級": 0, "中": 1, "中級": 1, "上": 2, "上級": 2]
        return values.sorted {
            let left = order[$0] ?? 3
            let right = order[$1] ?? 3
            return left == right ? $0.localizedStandardCompare($1) == .orderedAscending : left < right
        }
    }
    var categories: [String] {
        Array(Set(allQuestions.filter {
            $0.kai == searchKai && (searchLevel.isEmpty || $0.level == searchLevel)
        }.map(\.category))).sorted()
    }

    static func levelTitle(_ value: String) -> String {
        switch value {
        case "初", "中", "上": return value + "級"
        default: return value
        }
    }

    init() { load() }

    func load() {
        guard !isBusy else { return }
        isBusy = true
        notice = ""
        workQueue.async { [dao] in
            let result = Result { try dao.initialize(); return try dao.selectAll() }
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let questions):
                    self.isReady = true
                    self.replaceSnapshot(questions)
                case .failure(let error):
                    self.isReady = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func replaceSnapshot(_ snapshot: [Mondai]) {
        allQuestions = snapshot
        if !kais.contains(searchKai) { searchKai = kais.first ?? "" }
        reconcileSelections()
        applyFilters()
    }

    private func reconcileSelections() {
        if !searchLevel.isEmpty && !levels.contains(searchLevel) { searchLevel = "" }
        if !searchCategory.isEmpty && !categories.contains(searchCategory) { searchCategory = "" }
    }

    func selectKai(_ value: String) {
        guard isReady, !isBusy else { return }
        searchKai = value
        searchLevel = ""
        searchCategory = ""
        reconcileSelections()
        applyFilters()
    }

    func selectLevel(_ value: String) {
        guard isReady, !isBusy else { return }
        searchLevel = value
        searchCategory = ""
        reconcileSelections()
        applyFilters()
    }

    func selectCategory(_ value: String) {
        guard isReady, !isBusy else { return }
        searchCategory = value
        reconcileSelections()
        applyFilters()
    }

    func search() {
        guard isReady, !isBusy else { return }
        appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilters()
    }

    private func applyFilters() {
        guard isReady, !isBusy else { return }
        questions = allQuestions.filter { item in
            guard item.kai == searchKai,
                  searchLevel.isEmpty || item.level == searchLevel,
                  searchCategory.isEmpty || item.category == searchCategory else { return false }
            return appliedKeyword.isEmpty || ([item.category, item.question, item.description] + item.choices)
                .contains { $0.localizedCaseInsensitiveContains(appliedKeyword) }
        }
        show(at: 0)
    }

    func show(at index: Int) {
        guard !isBusy else { return }
        selectedChoice = nil
        revealsAnswer = false
        guard !questions.isEmpty else { current = 0; choices = []; return }
        current = min(max(0, index), questions.count - 1)
        choices = questions[current].choices.shuffled()
    }

    /// 入力画面のコピーを保存し、DB保存と表示の再読込を区別して通知する。
    func saveQuestion(_ question: Mondai, isNew: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isReady, !isBusy else {
            completion(.failure(AppError(message: "現在保存できません。再読込後に試してください。")))
            return
        }
        var savedQuestion = question
        if isNew {
            let maximum = allQuestions.map(\.seq).max() ?? -1
            let next = maximum.addingReportingOverflow(1)
            guard !next.overflow else {
                completion(.failure(AppError(message: "通番が上限に達しているため登録できません。")))
                return
            }
            savedQuestion.seq = max(0, next.partialValue)
        }
        do { try savedQuestion.validate() }
        catch { completion(.failure(error)); return }
        let item = savedQuestion
        isBusy = true
        workQueue.async { [dao] in
            do {
                let savedID: Int
                if isNew { savedID = try dao.insert(item) }
                else { try dao.update(item); savedID = item.id }
                let reload = Result { try dao.selectAll() }
                DispatchQueue.main.async {
                    self.isBusy = false
                    switch reload {
                    case .success(let snapshot):
                        self.replaceSnapshot(snapshot)
                        if let index = self.questions.firstIndex(where: { $0.id == savedID }) {
                            self.show(at: index)
                            self.notice = isNew ? "問題を登録しました。" : "問題を更新しました。"
                        } else {
                            self.notice = "保存しました。この問題は現在の検索条件に一致しないため、一覧には表示されません。"
                        }
                    case .failure(let error):
                        self.isReady = false
                        self.errorMessage = "保存は完了しましたが、一覧の再読込に失敗しました。再登録せず再読込してください。\n\(error.localizedDescription)"
                    }
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    completion(.failure(error))
                }
            }
        }
    }

    func deleteQuestion(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isReady, !isBusy else {
            completion(.failure(AppError(message: "現在削除できません。再読込後に試してください。")))
            return
        }
        // 削除後の検索結果に残る次の問題、なければ前の問題を優先する。
        let remainingIDs = questions.map(\.id).filter { $0 != id }
        let neighborID = remainingIDs.isEmpty ? nil : remainingIDs[min(current, remainingIDs.count - 1)]
        isBusy = true
        workQueue.async { [dao] in
            do {
                try dao.delete(id: id)
                let reload = Result { try dao.selectAll() }
                DispatchQueue.main.async {
                    self.isBusy = false
                    switch reload {
                    case .success(let snapshot):
                        self.replaceSnapshot(snapshot)
                        if let neighborID = neighborID,
                           let index = self.questions.firstIndex(where: { $0.id == neighborID }) {
                            self.show(at: index)
                        }
                        self.notice = "問題を削除しました。"
                    case .failure(let error):
                        self.isReady = false
                        self.errorMessage = "削除は完了しましたが、一覧の再読込に失敗しました。再読込してください。\n\(error.localizedDescription)"
                    }
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    completion(.failure(error))
                }
            }
        }
    }

    func prepareImport(_ url: URL) {
        guard isReady, !isBusy else { return }
        pendingImport = []
        notice = ""
        isBusy = true
        workQueue.async {
            let result = Result { try QuestionFileCodec.read(url) }
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let questions): self.pendingImport = questions
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelImport() { pendingImport = [] }

    func importQuestions(replacing: Bool, selectedKais: Set<String>) {
        guard isReady, !isBusy, !pendingImport.isEmpty else { return }
        let imported = pendingImport.filter { selectedKais.contains($0.kai) }
        guard !imported.isEmpty else { return }
        pendingImport = []
        isBusy = true
        workQueue.async { [dao] in
            do {
                try dao.importQuestions(imported, replacing: replacing)
                // コミット後の再読込失敗は、取込失敗とは区別して案内する。
                let result = Result { try dao.selectAll() }
                DispatchQueue.main.async {
                    self.isBusy = false
                    switch result {
                    case .success(let questions):
                        self.replaceSnapshot(questions)
                        self.notice = "\(imported.count)問を\(replacing ? "置換" : "追加")しました。"
                    case .failure(let error):
                        self.isReady = false
                        self.errorMessage = "取込は完了しましたが、表示の再読込に失敗しました。再読込してください。\n\(error.localizedDescription)"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.errorMessage = "取込を中止しました。既存データは保持されています。\n\(error.localizedDescription)"
                }
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dm = DataManager()
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = QuestionFileDocument()
    @State private var exportFormat = QuestionFileFormat.csv
    @State private var choosingExportFormat = false
    @State private var selectingImport = false
    @State private var showingAbout = false
    @State private var editorSession: QuestionEditorSession?
    @State private var movesForward = true
    @State private var isSwipeAnimating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if dm.isBusy { ProgressView("処理中…").frame(maxWidth: .infinity) }
                    if !dm.isReady && !dm.isBusy {
                        ContentUnavailableView("データを読み込めません", systemImage: "externaldrive.badge.exclamationmark",
                                               description: Text("再読込を試してください。既存DBは自動削除しません。"))
                        Button("再読込") { dm.load() }.buttonStyle(.borderedProminent)
                    }
                    searchControls
                        .disabled(!dm.isReady || dm.isBusy)
                    Divider()
                    if let question = dm.question, dm.isReady {
                        questionView(question)
                            .id(question.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: movesForward ? .trailing : .leading),
                                removal: .move(edge: movesForward ? .leading : .trailing)
                            ))
                    } else if dm.isReady {
                        ContentUnavailableView("問題がありません", systemImage: "doc.text.magnifyingglass",
                                               description: Text(dm.allQuestions.isEmpty ? "メニューからデータをインポートしてください。" : "検索条件を変更してください。"))
                    }
                    if !dm.notice.isEmpty { Text(dm.notice).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding()
            }
            .disabled(isSwipeAnimating)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                navigationControls
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.clear)
            }
            .navigationTitle("Kanazawa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新規", systemImage: "plus") {
                            editorSession = QuestionEditorSession(question: nil)
                        }.disabled(!dm.isReady || dm.isBusy)
                        Button("編集", systemImage: "square.and.pencil") {
                            if let question = dm.question {
                                editorSession = QuestionEditorSession(question: question)
                            }
                        }.disabled(!dm.isReady || dm.isBusy || dm.question == nil)
                        Divider()
                        Button("インポート", systemImage: "square.and.arrow.down") { importing = true }
                            .disabled(!dm.isReady || dm.isBusy)
                        Button("エクスポート", systemImage: "square.and.arrow.up") {
                            choosingExportFormat = true
                        }.disabled(!dm.isReady || dm.isBusy || dm.allQuestions.isEmpty)
                        Divider()
                        Button("About", systemImage: "info.circle") { showingAbout = true }
                    } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("データ管理")
                    .disabled(isSwipeAnimating)
                }
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(item: $editorSession) { session in
                QuestionEditorView(dm: dm, question: session.question)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .plainText, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { dm.prepareImport(url) }
                case .failure(let error): dm.errorMessage = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportFormat.contentType,
                          defaultFilename: "KanazawaData." + exportFormat.fileExtension) { result in
                switch result {
                case .success: dm.notice = "全\(dm.allQuestions.count)問を\(exportFormat.rawValue)で書き出しました。"
                case .failure(let error): dm.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("エクスポート形式", isPresented: $choosingExportFormat, titleVisibility: .visible) {
                Button("JSON") { beginExport(.json) }
                Button("CSV") { beginExport(.csv) }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("検索条件にかかわらず全問題を書き出します。")
            }
            .onChange(of: dm.pendingImport.count) { _, count in
                if count > 0 { selectingImport = true }
            }
            .sheet(isPresented: $selectingImport, onDismiss: { dm.cancelImport() }) {
                ImportSelectionView(questions: dm.pendingImport, existingCount: dm.allQuestions.count) { selectedKais, replacing in
                    dm.importQuestions(replacing: replacing, selectedKais: selectedKais)
                }
            }
            .alert("処理に失敗しました", isPresented: Binding(get: { dm.errorMessage != nil }, set: { if !$0 { dm.errorMessage = nil } })) {
                Button("閉じる", role: .cancel) { dm.errorMessage = nil }
            } message: { Text(dm.errorMessage ?? "") }
        }
    }

    private func beginExport(_ format: QuestionFileFormat) {
        guard dm.isReady, !dm.isBusy, !dm.allQuestions.isEmpty else { return }
        do {
            let data = try QuestionFileCodec.encode(dm.allQuestions, format: format)
            exportFormat = format
            exportDocument = QuestionFileDocument(data: data)
            exporting = true
        } catch { dm.errorMessage = error.localizedDescription }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                HStack {
                    Text("実施回").fixedSize()
                    Picker("実施回", selection: Binding(get: { dm.searchKai }, set: { dm.selectKai($0) })) {
                        if dm.kais.isEmpty { Text("なし").tag("") }
                        ForEach(dm.kais, id: \.self) { Text("第\($0)回").tag($0) }
                    }
                    .labelsHidden()
                }
                Spacer(minLength: 0)
                HStack {
                    Text("級").fixedSize()
                    Picker("級", selection: Binding(get: { dm.searchLevel }, set: { dm.selectLevel($0) })) {
                        Text("すべて").tag("")
                        ForEach(dm.levels, id: \.self) { Text(DataManager.levelTitle($0)).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(dm.levels.isEmpty)
                }
            }
            HStack {
                Text("分類").fixedSize()
                Picker("分類", selection: Binding(get: { dm.searchCategory }, set: { dm.selectCategory($0) })) {
                    Text("すべて").tag("")
                    ForEach(dm.categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(dm.categories.isEmpty)
            }
            HStack {
                TextField("検索キーワード", text: $dm.keyword)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { dm.search() }
                Button("検索") { dm.search() }.buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(dm.questions.count)件")
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .pickerStyle(.menu)
    }

    private var navigationControls: some View {
        HStack {
            Button { dm.show(at: 0) } label: { Image(systemName: "backward.end").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("最初の問題")
                .disabled(dm.current == 0)
            Button { dm.show(at: dm.current - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("前の問題")
                .disabled(dm.current == 0)
            Spacer()
            Text(dm.position).monospacedDigit()
            Spacer()
            Button { dm.show(at: dm.current + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("次の問題")
                .disabled(dm.current >= dm.questions.count - 1)
            Button { dm.show(at: dm.questions.count - 1) } label: { Image(systemName: "forward.end").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("最後の問題")
                .disabled(dm.current >= dm.questions.count - 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .frame(minHeight: 44)
        .disabled(!dm.isReady || dm.isBusy || dm.questions.isEmpty || isSwipeAnimating)
    }

    private func questionView(_ question: Mondai) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("第\(question.kai)回・\(DataManager.levelTitle(question.level))　問題\(question.number)")
                    .font(.headline)
                Text(question.category).font(.subheadline).foregroundStyle(.secondary)
                Text(question.question.isEmpty ? "この問題は未入力です。" : question.question)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(dm.choices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        dm.selectedChoice = index
                        dm.revealsAnswer = true
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: dm.selectedChoice == index ? "checkmark.circle.fill" : "circle")
                            Text(choice.isEmpty ? "未入力" : choice)
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(choice.isEmpty || dm.isBusy)
                    .accessibilityLabel("選択肢\(index + 1)：\(choice)")
                }
            }
            .padding(8)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            }
            Button(dm.revealsAnswer ? "答え・解説を隠す" : "答え・解説を表示") { dm.revealsAnswer.toggle() }
                .buttonStyle(.bordered).disabled(dm.isBusy)
            if dm.revealsAnswer {
                Divider()
                Text("答え：\(question.answer.isEmpty ? "未入力" : question.answer)").font(.headline)
                Text(question.description)
                if !question.hiduke.isEmpty { Text("実施日：\(question.hiduke)").font(.footnote) }
                if !question.bikou.isEmpty { Text("備考：\(question.bikou)").font(.footnote) }
            }
        }
        .textSelection(.enabled)
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { gesture in
            guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.5 else { return }
            moveBySwipe(forward: gesture.translation.width < 0)
        })
    }

    private func moveBySwipe(forward: Bool) {
        guard dm.isReady, !dm.isBusy, !isSwipeAnimating else { return }
        let destination = dm.current + (forward ? 1 : -1)
        guard dm.questions.indices.contains(destination) else { return }
        movesForward = forward
        isSwipeAnimating = true
        withAnimation(.easeInOut(duration: 0.25), completionCriteria: .removed) {
            dm.show(at: destination)
        } completion: {
            isSwipeAnimating = false
        }
    }

}
