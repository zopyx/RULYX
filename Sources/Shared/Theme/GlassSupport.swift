import SwiftUI

// MARK: - Glass Button Styles

extension View {
    /// Prominent button style — uses iOS 26 glass effect or falls back to `.borderedProminent`.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Bordered button style — uses iOS 26 glass effect or falls back to `.bordered`.
    @ViewBuilder
    func glassBorderedButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

// MARK: - Glass Background

extension View {
    /// Apply a glass/material background with the given shape.
    /// Uses iOS 26 `glassEffect` or falls back to `.thinMaterial`.
    @ViewBuilder
    func glassBackground(in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        if #available(iOS 26, *) {
            background(Color.clear.glassEffect(.regular, in: shape))
        } else {
            background(.thinMaterial, in: shape)
        }
    }

    /// Apply a tinted glass background with the given tint color and shape.
    @ViewBuilder
    func glassTintedBackground(tint: Color, in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        if #available(iOS 26, *) {
            background(Color.clear.glassEffect(.regular.tint(tint), in: shape))
        } else {
            background(tint.opacity(0.12), in: shape)
        }
    }
}

// MARK: - Account Tint Colors

extension Color {
    /// Maps an account tint string identifier to a SwiftUI Color.
    static func accountTint(_ identifier: String?) -> Color {
        switch identifier {
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "pink": .pink
        default: .skyPrimary
        }
    }

    /// All available account tint color identifiers.
    static let accountTintOptions: [(id: String, color: Color)] = [
        ("blue", .skyPrimary),
        ("green", .green),
        ("orange", .orange),
        ("purple", .purple),
        ("red", .red),
        ("teal", .teal),
        ("pink", .pink),
    ]
}

// MARK: - Account Switcher Toolbar

extension View {
    /// Toolbar content for an account switcher button in `.topBarLeading` position.
    /// Shows the active account's avatar, display name, and chevron.
    /// Tapping opens an inline menu for quick switching; "Manage Accounts" triggers the callback.
    func accountSwitcherToolbar(
        accountStore: AccountStore,
        blueskyClient: LiveBlueskyClient,
        workspaceStore: ModerationWorkspaceStore,
        localizationManager: LocalizationManager,
        onManageAccounts: (() -> Void)? = nil
    ) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let account = accountStore.activeAccount {
                Menu {
                    ForEach(accountStore.accounts) { acct in
                        Button {
                            switchTo(acct, store: accountStore, client: blueskyClient, workspace: workspaceStore)
                        } label: {
                            HStack {
                                accountMenuLabel(for: acct, isActive: acct.id == accountStore.activeAccountID, store: accountStore)
                            }
                        }
                        .disabled(acct.id == accountStore.activeAccountID || accountStore.isDeactivated(acct))
                    }

                    if !accountStore.accounts.isEmpty {
                        Divider()
                    }

                    if let onManageAccounts {
                        Button {
                            onManageAccounts()
                        } label: {
                            Label(loc("account.switcher.manage"), systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        accountAvatarView(for: account, tint: .accountTint(account.tintColor))

                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuOrder(.fixed)
                .accessibilityLabel(localizationManager.localized("account.switcher.label"))
                .accessibilityHint(localizationManager.localized("account.switcher.hint"))
            } else {
                Button {
                    onManageAccounts?()
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(localizationManager.localized("account.switcher.label"))
            }
        }
    }

    /// Switch to the given account with haptic feedback.
    private func switchTo(_ account: AppAccount, store: AccountStore, client: LiveBlueskyClient, workspace: ModerationWorkspaceStore) {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        Task {
            await store.switchAccount(to: account, using: client)
            workspace.returnToModerationRoot()
            generator.selectionChanged()
        }
    }

    /// Build the label for an account menu item: tint dot, avatar, display name, checkmark if active.
    private func accountMenuLabel(for account: AppAccount, isActive: Bool, store: AccountStore) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.accountTint(account.tintColor))
                .frame(width: 10, height: 10)

            accountAvatarView(for: account, tint: .accountTint(account.tintColor), size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(account.handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
            }

            if store.isDeactivated(account) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if account.id == store.activeAccountID {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    /// Render an account's avatar (async image or initial-letter placeholder).
    @ViewBuilder
    func accountAvatarView(for account: AppAccount, tint: Color = .skyPrimary, size: CGFloat = 28) -> some View {
        if let avatarURL = account.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(tint)
                    .overlay {
                        Text(account.displayName.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .overlay {
                    Text(account.displayName.prefix(1).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }
}
