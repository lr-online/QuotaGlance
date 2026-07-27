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
                    VStack(spacing: 6) {
                        Label("No Accounts", systemImage: "key.horizontal")
                            .font(.headline)
                        Text("Add a provider account to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
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
                }
                .disabled(model.accounts.count >= 5)
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
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Label(
                    notificationStatus,
                    systemImage: model.notificationPermission == .authorized
                        ? "checkmark.circle"
                        : "bell.slash"
                )
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func accountRow(_ account: Account, index: Int) -> some View {
        HStack(spacing: 10) {
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

            Spacer()

            Button {
                model.moveAccount(id: account.id, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move Up")

            Button {
                model.moveAccount(id: account.id, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == model.accounts.count - 1)
            .help("Move Down")

            Button {
                editorContext = AccountEditorContext(account: account)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit Account")

            Button(role: .destructive) {
                accountToDelete = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Account")
        }
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
