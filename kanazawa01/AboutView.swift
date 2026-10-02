import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "不明"
    }

    private var revision: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image("AboutIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("Kanazawaのアイコン：金色の加賀梅鉢")
                    Text("Kanazawa").font(.title.bold())
                    VStack(spacing: 12) {
                        Text("Version：\(version)")
                        Text("Revision：\(revision)")
                    }
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .navigationTitle("Kanazawaについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
