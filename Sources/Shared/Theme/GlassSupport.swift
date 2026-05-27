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

// MARK: - Account Switcher Toolbar

extension View {
    /// Toolbar content for an account switcher button in `.topBarLeading` position.
    /// Shows the active account's avatar, display name, and chevron.
    func accountSwitcherToolbar(isPresented: Binding<Bool>, accountStore: AccountStore, localizationManager: LocalizationManager) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isPresented.wrappedValue = true
            } label: {
                HStack(spacing: 8) {
                    if let account = accountStore.activeAccount {
                        accountAvatarView(for: account)

                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizationManager.localized("account.switcher.label"))
            .accessibilityHint(localizationManager.localized("account.switcher.hint"))
        }
    }

    /// Render the active account's avatar (async image or initial-letter placeholder).
    @ViewBuilder
    func accountAvatarView(for account: AppAccount) -> some View {
        let avatarSize: CGFloat = 28
        if let avatarURL = account.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.skyPrimary)
                    .overlay {
                        Text(account.displayName.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.skyPrimary)
                .frame(width: avatarSize, height: avatarSize)
                .overlay {
                    Text(account.displayName.prefix(1).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }
}
