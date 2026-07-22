import QuotaGlanceCore
import SwiftUI

struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let model: AppModel
    let account: Account?

    @State private var draft: AccountDraft
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(model: AppModel, account: Account?) {
        self.model = model
        self.account = account
        _draft = State(
            initialValue: AccountDraft(
                displayName: account?.displayName ?? "",
                apiKey: "",
                isEnabled: account?.isEnabled ?? true,
                lowBalanceThresholdText: account?.lowBalanceThreshold.map {
                    NSDecimalNumber(decimal: $0).stringValue
                } ?? ""
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.displayName)
                SecureField(
                    account == nil ? "API Key" : "Replacement API Key (Optional)",
                    text: $draft.apiKey
                )
                TextField(
                    "Low Balance Threshold (Optional)",
                    text: $draft.lowBalanceThresholdText
                )
                Toggle("Enabled", isOn: $draft.isEnabled)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding(16)
        }
        .frame(width: 430, height: 310)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.saveAccount(draft: draft, editing: account?.id)
                dismiss()
            } catch {
                errorMessage = model.message(for: error)
                isSaving = false
            }
        }
    }
}
