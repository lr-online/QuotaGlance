import QuotaGlanceCore
import SwiftUI

struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: AppModel
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
                provider: account?.provider ?? .apiInfo,
                isEnabled: account?.isEnabled ?? true,
                lowBalanceThresholdText: Self.thresholdText(for: account)
            )
        )
    }

    private var selectedProfile: ProviderProfile? {
        guard draft.provider == account?.provider else { return nil }
        return account?.detectedProfile
    }

    private var supportsLowBalanceThreshold: Bool {
        draft.provider.supportsLowBalanceThreshold(profile: selectedProfile)
    }

    private var providerSelection: Binding<ProviderID> {
        Binding(
            get: { draft.provider },
            set: { provider in
                draft.provider = provider
                if !provider.supportsLowBalanceThreshold(
                    profile: selectedProfile
                ) {
                    draft.lowBalanceThresholdText = ""
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Provider", selection: providerSelection) {
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField("Name", text: $draft.displayName)
                SecureField(
                    account == nil ? "API Key" : "Replacement API Key (Optional)",
                    text: $draft.apiKey
                )
                if supportsLowBalanceThreshold {
                    TextField(
                        thresholdFieldLabel,
                        text: $draft.lowBalanceThresholdText
                    )
                }
                Toggle("Enabled", isOn: $draft.isEnabled)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .compatibleGroupedFormStyle()

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
        .frame(width: 430, height: 340)
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

    private var thresholdFieldLabel: String {
        if draft.provider == .openRouter {
            return "Management Key Low Balance Threshold (Optional)"
        }
        return "Low Balance Threshold (Optional)"
    }

    private static func thresholdText(for account: Account?) -> String {
        guard let account,
              account.provider.supportsLowBalanceThreshold(
                  profile: account.detectedProfile
              ),
              let threshold = account.lowBalanceThreshold else {
            return ""
        }
        return NSDecimalNumber(decimal: threshold).stringValue
    }
}
