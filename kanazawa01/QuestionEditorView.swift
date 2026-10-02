import SwiftUI

/// 開くたびに別の入力状態を作り、編集中に表示対象が変わっても編集IDを固定する。
struct QuestionEditorSession: Identifiable {
    let id = UUID()
    let question: Mondai?
}

private struct QuestionDraft: Equatable {
    var id: Int
    var seq: Int
    var kai: String
    var level: String
    var category: String
    var number: String
    var question: String
    var sel1: String
    var sel2: String
    var sel3: String
    var sel4: String
    var answer: String
    var explanation: String
    var date: String
    var notes: String

    init(_ item: Mondai?) {
        id = item?.id ?? 0
        seq = item?.seq ?? 0
        kai = item?.kai ?? ""
        level = item?.level ?? ""
        category = item?.category ?? ""
        number = item.map { String($0.number) } ?? ""
        question = item?.question ?? ""
        sel1 = item?.sel1 ?? ""
        sel2 = item?.sel2 ?? ""
        sel3 = item?.sel3 ?? ""
        sel4 = item?.sel4 ?? ""
        answer = item?.answer ?? ""
        explanation = item?.description ?? ""
        date = item?.hiduke ?? ""
        notes = item?.bikou ?? ""
    }

    func makeQuestion() throws -> Mondai {
        guard let value = Int(number.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            throw AppError(message: "問題番号は1以上の整数にしてください。")
        }
        let item = Mondai(id: id, seq: seq,
                          kai: kai.trimmingCharacters(in: .whitespacesAndNewlines), level: level,
                          category: category.trimmingCharacters(in: .whitespacesAndNewlines), number: value,
                          question: question, sel1: sel1, sel2: sel2, sel3: sel3, sel4: sel4,
                          answer: answer, description: explanation, hiduke: date, bikou: notes)
        try item.validate()
        return item
    }
}

struct QuestionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dm: DataManager
    @State private var draft: QuestionDraft
    @State private var isSaving = false
    @State private var confirmsDiscard = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    private let original: QuestionDraft
    private let isNew: Bool

    init(dm: DataManager, question: Mondai?) {
        self.dm = dm
        let initial = QuestionDraft(question)
        original = initial
        isNew = question == nil
        _draft = State(initialValue: initial)
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            Form {
                if isSaving || isDeleting { ProgressView(isDeleting ? "削除中…" : "保存中…") }
                if let errorMessage = errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section("問題情報") {
                    HStack(alignment: .top, spacing: 16) {
                        Text("実施回")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.kai)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("実施回（必須）")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("級")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        Picker("級（必須）", selection: $draft.level) {
                            Text("選択してください").tag("")
                            Text("初級").tag("初")
                            Text("中級").tag("中")
                            Text("上級").tag("上")
                            // 既存CSVの表記を勝手に変更しない。
                            if !draft.level.isEmpty && !["初", "中", "上"].contains(draft.level) {
                                Text(DataManager.levelTitle(draft.level)).tag(draft.level)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("分類")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("分類を入力", text: $draft.category, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("分類")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("問題番号")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.number)
                            .keyboardType(.numberPad)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("問題番号（必須）")
                    }
                }
                Section("問題文（必須）") {
                    TextField("問題文", text: $draft.question, axis: .vertical).lineLimit(4...12)
                }
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        Text("選択肢1")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.sel1, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("選択肢1（必須）")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("選択肢2")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.sel2, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("選択肢2（必須）")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("選択肢3")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.sel3, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("選択肢3（必須）")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("選択肢4")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("必須", text: $draft.sel4, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("選択肢4（必須）")
                    }
                } header: { Text("選択肢（すべて必須）") }
                  footer: { Text("登録順で表示しています。問題画面では順番がシャッフルされます。") }
                Section("答え（必須）") {
                    TextField("答え", text: $draft.answer, axis: .vertical)
                }
                Section("解説") {
                    TextField("解説", text: $draft.explanation, axis: .vertical).lineLimit(4...12)
                }
                Section("その他") {
                    HStack(alignment: .top, spacing: 16) {
                        Text("実施日")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("任意", text: $draft.date)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("実施日")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Text("備考")
                            .foregroundStyle(.gray)
                            .frame(width: 88, alignment: .leading)
                        TextField("任意", text: $draft.notes, axis: .vertical)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("備考")
                    }
                }
            }
            .disabled(isSaving || isDeleting)
            .navigationTitle(isNew ? "問題の新規登録" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { requestClose() } label: {
                        Text("キャンセル")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                        .disabled(isSaving || isDeleting)
                }
                if !isNew {
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarLeading)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) { confirmsDeletion = true } label: {
                            Text("削除")
                                .fixedSize(horizontal: true, vertical: false)
                        }
                            .tint(.red)
                            .foregroundStyle(Color.red)
                            .disabled(isSaving || isDeleting || !dm.isReady || dm.isBusy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving || isDeleting || !dm.isReady || dm.isBusy || (!isNew && !hasChanges))
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving || isDeleting)
            .alert("入力内容を破棄しますか？", isPresented: $confirmsDiscard) {
                Button("破棄して閉じる", role: .destructive) { dismiss() }
                Button("入力を続ける", role: .cancel) { }
            } message: { Text("保存していない変更があります。") }
            .alert("この問題を削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除する", role: .destructive) { deleteQuestion() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("第\(original.kai)回・\(DataManager.levelTitle(original.level))・問題\(original.number)を削除します。この操作は取り消せません。未保存の変更も破棄されます。")
            }
        }
    }

    private func requestClose() {
        guard !isSaving, !isDeleting else { return }
        if hasChanges { confirmsDiscard = true }
        else { dismiss() }
    }

    private func save() {
        guard !isSaving, !isDeleting else { return }
        errorMessage = nil
        do {
            let item = try draft.makeQuestion()
            isSaving = true
            dm.saveQuestion(item, isNew: isNew) { result in
                isSaving = false
                switch result {
                case .success: dismiss()
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteQuestion() {
        guard !isNew, !isSaving, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        dm.deleteQuestion(id: original.id) { result in
            isDeleting = false
            switch result {
            case .success: dismiss()
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

}
