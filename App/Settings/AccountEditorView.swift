import AppKit
import QuotaGlanceCore
import SwiftUI
import UniformTypeIdentifiers

struct AccountEditorView: View {
    private enum Field: Hashable {
        case name
        case apiKey
        case threshold
    }

    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: AppModel
    let account: Account?

    @State private var draft: AccountDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

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
                    .focused($focusedField, equals: .name)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SecureField(
                        account == nil
                            ? "API Key"
                            : "Replacement API Key (Optional)",
                        text: $draft.apiKey
                    )
                    .focused($focusedField, equals: .apiKey)
                    .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in
                        pasteAPIKey()
                    }
                    Button("Paste") {
                        pasteAPIKey()
                    }
                    .help("Paste API key from clipboard (⌘V)")
                }
                if supportsLowBalanceThreshold {
                    TextField(
                        thresholdFieldLabel,
                        text: $draft.lowBalanceThresholdText
                    )
                    .focused($focusedField, equals: .threshold)
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
        .frame(width: 460, height: 340)
        .background(APIKeyPasteShortcutBridge(isAPIKeyFocused: focusedField == .apiKey) {
            pasteAPIKey()
        })
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

    private func pasteAPIKey() {
        guard let string = NSPasteboard.general.string(forType: .string) else {
            return
        }
        draft.apiKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// SecureField often fails to accept Cmd+V in accessory apps; when the API key
/// field is focused, consume ⌘V locally and write the pasteboard into the draft.
private struct APIKeyPasteShortcutBridge: NSViewRepresentable {
    var isAPIKeyFocused: Bool
    var onPaste: () -> Void

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isAPIKeyFocused = isAPIKeyFocused
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: BridgeView, context: Context) {
        nsView.isAPIKeyFocused = isAPIKeyFocused
        nsView.onPaste = onPaste
    }

    final class BridgeView: NSView {
        var isAPIKeyFocused = false
        var onPaste: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                startMonitor()
            } else {
                stopMonitor()
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func startMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                guard self.isAPIKeyFocused,
                      flags == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "v"
                else {
                    return event
                }
                self.onPaste?()
                return nil
            }
        }

        private func stopMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
