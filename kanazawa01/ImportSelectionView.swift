import SwiftUI

struct ImportSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKais: Set<String> = []
    @State private var confirmsReplacement = false

    private let existingCount: Int
    private let onImport: (Set<String>, Bool) -> Void
    private let counts: [String: Int]
    private let kais: [String]

    init(questions: [Mondai], existingCount: Int, onImport: @escaping (Set<String>, Bool) -> Void) {
        self.existingCount = existingCount
        self.onImport = onImport
        let grouped = Dictionary(grouping: questions, by: \.kai).mapValues { $0.count }
        counts = grouped
        kais = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedCount: Int {
        selectedKais.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(kais, id: \.self) { kai in
                        Button {
                            toggleSelection(kai)
                        } label: {
                            HStack {
                                Image(systemName: selectedKais.contains(kai) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                Text("第\(kai)回").foregroundStyle(.primary)
                                Spacer()
                                Text("\(counts[kai] ?? 0)件").foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("第\(kai)回、\(counts[kai] ?? 0)件")
                        .accessibilityAddTraits(selectedKais.contains(kai) ? .isSelected : [])
                    }
                } header: { Text("インポートする実施回") }
                  footer: { Text("複数の実施回を選択できます。") }
                Section {
                    Text("選択：\(selectedKais.count)回・\(selectedCount)件")
                        .monospacedDigit()
                    Button("既存データに追加") { importSelection(replacing: false) }
                        .disabled(selectedCount == 0)
                    Button("既存データを置換", role: .destructive) { confirmsReplacement = true }
                        .disabled(selectedCount == 0)
                } footer: {
                    Text("追加は同じ問題も登録します。置換は選択した回だけでDB全体を入れ替えます。選択していない回の既存データも削除されます。")
                }
            }
            .navigationTitle("インポートする回を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .alert("DB全体を置換しますか？", isPresented: $confirmsReplacement) {
                Button("置換する", role: .destructive) { importSelection(replacing: true) }
                Button("選択に戻る", role: .cancel) { }
            } message: {
                Text("現在の全\(existingCount)件を削除し、選択した\(selectedKais.count)回・\(selectedCount)件に置き換えます。必要なら先にエクスポートしてください。")
            }
        }
    }

    private func toggleSelection(_ kai: String) {
        if selectedKais.contains(kai) { selectedKais.remove(kai) }
        else { selectedKais.insert(kai) }
    }

    private func importSelection(replacing: Bool) {
        guard selectedCount > 0 else { return }
        onImport(selectedKais, replacing)
        dismiss()
    }
}
