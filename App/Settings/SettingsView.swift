import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var editorContext: AccountEditorContext?
    @State private var accountToDelete: Account?

    var body: some View {
        Form {
            Section("Accounts") {
                if model.accounts.isEmpty {
                    emptyAccountsPlaceholder
                } else {
                    ForEach(Array(model.accounts.enumerated()), id: \.element.id) {
                        index, account in
                        accountRow(account, index: index)
                    }
                }

                Button {
                    editorContext = AccountEditorContext(account: nil)
                } label: {
                    Label("Add Account", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, 2)
                .disabled(
                    model.accounts.count >= AccountValidator.maximumAccountCount
                )
            }

            Section("Refresh") {
                Picker(
                    "Interval",
                    selection: Binding(
                        get: { model.preferences.refreshInterval },
                        set: { model.setRefreshInterval($0) }
                    )
                ) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(intervalTitle(interval)).tag(interval)
                    }
                }

                if model.supportsLaunchAtLogin {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.preferences.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                }
            }

            if let error = model.lastErrorMessage {
                Section("Status") {
                    Label {
                        Text(error)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Section {
                HStack {
                    Label {
                        Text("Low Balance Alerts")
                    } icon: {
                        Image(
                            systemName: model.notificationPermission == .authorized
                                ? "checkmark.circle.fill"
                                : "bell.slash"
                        )
                        .foregroundStyle(
                            model.notificationPermission == .authorized
                                ? Color.green
                                : Color.secondary
                        )
                    }
                    Spacer()
                    Text(notificationStatus)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "QuotaGlance notifies you when an account balance drops below its alert threshold."
                )
            }
        }
        .compatibleGroupedFormStyle()
        .frame(minWidth: 560, minHeight: 460)
        .sheet(item: $editorContext) { context in
            AccountEditorView(model: model, account: context.account)
        }
        .alert(
            "Delete Account?",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            ),
            presenting: accountToDelete
        ) { account in
            Button("Delete", role: .destructive) {
                Task { await model.deleteAccount(id: account.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(account.displayName)
        }
    }

    private var emptyAccountsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Accounts")
                .font(.headline)
            Text("Add a provider account to begin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func accountRow(_ account: Account, index: Int) -> some View {
        HStack(spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { account.isEnabled },
                    set: { model.setAccountEnabled(id: account.id, isEnabled: $0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                    Text(accountDetail(account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if model.accounts.count > 1 {
                    rowActionButton(
                        systemName: "chevron.up",
                        help: "Move Up",
                        isDisabled: index == 0
                    ) {
                        model.moveAccount(id: account.id, offset: -1)
                    }
                    rowActionButton(
                        systemName: "chevron.down",
                        help: "Move Down",
                        isDisabled: index == model.accounts.count - 1
                    ) {
                        model.moveAccount(id: account.id, offset: 1)
                    }
                }

                rowActionButton(systemName: "pencil", help: "Edit Account") {
                    editorContext = AccountEditorContext(account: account)
                }

                rowActionButton(
                    systemName: "trash",
                    help: "Delete Account",
                    tint: .red
                ) {
                    accountToDelete = account
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func rowActionButton(
        systemName: String,
        help: String,
        tint: Color = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .help(help)
    }

    private func intervalTitle(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .sixtyMinutes: "60 minutes"
        }
    }

    private func accountDetail(_ account: Account) -> String {
        var parts = [
            account.provider.displayName,
            account.provider.profileDescription(for: account.detectedProfile),
        ]
        if account.provider.supportsLowBalanceThreshold(
            profile: account.detectedProfile
        ), let threshold = account.lowBalanceThreshold {
            parts.append("Alert below \(NSDecimalNumber(decimal: threshold).stringValue)")
        }
        return parts.joined(separator: " - ")
    }

    private var notificationStatus: String {
        switch model.notificationPermission {
        case .notDetermined: "Not Requested"
        case .denied: "Not Allowed"
        case .authorized: "Allowed"
        }
    }
}

private struct AccountEditorContext: Identifiable {
    let id = UUID()
    let account: Account?
}
