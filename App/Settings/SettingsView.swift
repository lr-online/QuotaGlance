import AppKit
import QuotaGlanceCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var editorContext: AccountEditorContext?
    @State private var accountToDelete: Account?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountsSection
                refreshSection
                notificationCenterWidgetSection
                notificationsSection

                if let error = model.lastErrorMessage {
                    statusSection(error)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var accountsSection: some View {
        settingsSection(title: "Accounts") {
            if model.accounts.isEmpty {
                emptyAccountsPlaceholder
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) {
                    index, account in
                    if index > 0 {
                        settingsDivider
                    }
                    accountRow(account, index: index)
                }
            }

            settingsDivider

            Button {
                editorContext = AccountEditorContext(account: nil)
            } label: {
                Label("Add Account", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .disabled(
                model.accounts.count >= AccountValidator.maximumAccountCount
            )
        }
    }

    private var refreshSection: some View {
        settingsSection(title: "Refresh") {
            settingsRow {
                Text("Interval")
                Spacer(minLength: 12)
                Picker(
                    "",
                    selection: Binding(
                        get: { model.preferences.refreshInterval },
                        set: { model.setRefreshInterval($0) }
                    )
                ) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(intervalTitle(interval)).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 128, alignment: .trailing)
            }

            if model.supportsLaunchAtLogin {
                settingsDivider
                settingsRow {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.preferences.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var notificationCenterWidgetSection: some View {
        settingsSection(
            title: "Notification Center Widget",
            footer: "Applies to widgets still set to Use App Default. Widgets edited in Notification Center keep their own account."
        ) {
            settingsRow {
                Text("Default Account")
                Spacer(minLength: 12)
                Picker(
                    "",
                    selection: Binding(
                        get: { model.preferences.notificationCenterDefaultAccountID },
                        set: { model.setNotificationCenterDefaultAccountID($0) }
                    )
                ) {
                    Text("All Accounts").tag(Optional<UUID>.none)
                    ForEach(model.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 128, alignment: .trailing)
            }
        }
    }

    private var notificationsSection: some View {
        settingsSection(
            title: "Notifications",
            footer: "QuotaGlance notifies you when an account balance drops below its alert threshold."
        ) {
            settingsRow {
                Label {
                    Text("Low Balance Alerts")
                } icon: {
                    Image(systemName: notificationSymbol)
                        .foregroundStyle(notificationSymbolColor)
                }
                Spacer(minLength: 12)
                Text(notificationStatus)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func statusSection(_ error: String) -> some View {
        settingsSection(title: "Status") {
            settingsRow(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .padding(.top, 1)
                Text(error)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyAccountsPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Accounts")
                .font(.headline)
            Text("Add a provider account to begin.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func accountRow(_ account: Account, index: Int) -> some View {
        let detail = accountDetail(account)

        settingsRow(alignment: .top) {
            Toggle(
                "",
                isOn: Binding(
                    get: { account.isEnabled },
                    set: { model.setAccountEnabled(id: account.id, isEnabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.body)
                    .lineLimit(1)

                Text(detail.primary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondary = detail.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
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
            .padding(.top, 1)
        }
    }

    private func rowActionButton(
        systemName: String,
        help: String,
        tint: Color = .secondary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.35) : tint)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func settingsRow<Content: View>(
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 14)
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

    private func accountDetail(_ account: Account) -> (primary: String, secondary: String?) {
        let primary = [
            account.provider.displayName,
            account.provider.profileDescription(for: account.detectedProfile),
        ].joined(separator: " · ")

        guard account.provider.supportsLowBalanceThreshold(
            profile: account.detectedProfile
        ), let threshold = account.lowBalanceThreshold else {
            return (primary, nil)
        }

        return (
            primary,
            "Alert below \(NSDecimalNumber(decimal: threshold).stringValue)"
        )
    }

    private var notificationStatus: String {
        switch model.notificationPermission {
        case .notDetermined: "Not Requested"
        case .denied: "Not Allowed"
        case .authorized: "Allowed"
        }
    }

    private var notificationSymbol: String {
        switch model.notificationPermission {
        case .authorized: "checkmark.circle.fill"
        case .denied: "bell.slash"
        case .notDetermined: "bell"
        }
    }

    private var notificationSymbolColor: Color {
        switch model.notificationPermission {
        case .authorized: .green
        case .denied, .notDetermined: .secondary
        }
    }
}

private struct AccountEditorContext: Identifiable {
    let id = UUID()
    let account: Account?
}
