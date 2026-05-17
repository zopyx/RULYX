import SwiftUI

// MARK: - Button Styles

extension View {
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

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
    @ViewBuilder
    func glassBackground(in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        if #available(iOS 26, *) {
            background(Color.clear.glassEffect(.regular, in: shape))
        } else {
            background(.thinMaterial, in: shape)
        }
    }

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
