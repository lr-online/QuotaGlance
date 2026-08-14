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

    private let labelWidth: CGFloat = 88

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

    private var language: AppLanguage { model.resolvedLanguage }

    private var selectedProfile: ProviderProfile? {
        guard draft.provider == account?.provider else { return nil }
        return account?.detectedProfile
    }

    private var supportsLowBalanceThreshold: Bool {
        ProviderCatalog.descriptor(for: draft.provider)
            .supportsLowBalanceThreshold(selectedProfile)
    }

    private var providerSelection: Binding<ProviderID> {
        Binding(
            get: { draft.provider },
            set: { provider in
                draft.provider = provider
                if !ProviderCatalog.descriptor(for: provider)
                    .supportsLowBalanceThreshold(selectedProfile) {
                    draft.lowBalanceThresholdText = ""
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                labeledRow(L10n.string(.provider, language: language)) {
                    Picker("", selection: providerSelection) {
                        ForEach(ProviderID.allCases) { provider in
                            Text(ProviderCatalog.descriptor(for: provider).displayName)
                                .tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                labeledRow(L10n.string(.name, language: language)) {
                    TextField("", text: $draft.displayName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                labeledRow(
                    account == nil
                        ? L10n.string(.apiKey, language: language)
                        : L10n.string(.replacementAPIKey, language: language)
                ) {
                    HStack(spacing: 8) {
                        SecureField("", text: $draft.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .apiKey)
                            .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in
                                pasteAPIKey()
                            }
                        Button(L10n.string(.paste, language: language)) {
                            pasteAPIKey()
                        }
                        .help(L10n.string(.pasteAPIKeyHelp, language: language))
                        .fixedSize()
                    }
                }

                if supportsLowBalanceThreshold {
                    labeledRow(L10n.string(.threshold, language: language)) {
                        TextField("", text: $draft.lowBalanceThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .threshold)
                    }
                    Text(thresholdCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, labelWidth + 12)
                }

                Toggle(L10n.string(.enabled, language: language), isOn: $draft.isEnabled)
                    .toggleStyle(.checkbox)
                    .padding(.leading, labelWidth + 12)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, labelWidth + 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack {
                Button(L10n.string(.cancel, language: language), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(L10n.string(.save, language: language)) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(APIKeyPasteShortcutBridge(isAPIKeyFocused: focusedField == .apiKey) {
            pasteAPIKey()
        })
    }

    private func labeledRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(width: labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private var thresholdCaption: String {
        if draft.provider == .openRouter {
            return L10n.string(.openRouterThresholdCaption, language: language)
        }
        return L10n.string(.thresholdCaption, language: language)
    }

    private static func thresholdText(for account: Account?) -> String {
        guard let account,
              ProviderCatalog.descriptor(for: account.provider)
                  .supportsLowBalanceThreshold(account.detectedProfile),
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
        // NSEvent monitors must be removable from deinit; the token is opaque.
        nonisolated(unsafe) private var monitor: Any?

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
