import PhotosUI
import SwiftUI

/// A sheet for editing the authenticated account's profile: display name,
/// description, avatar, and banner. Fetches the current profile record on
/// appear so existing blob refs can be preserved when fields are not changed.
@MainActor
struct ProfileEditView: View {
    let account: AppAccount
    let appPassword: String?

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var displayName: String = ""
    @State private var description: String = ""

    // Avatar
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarImageData: Data?
    @State private var removeAvatar = false
    @State private var currentAvatarBlob: UploadedBlob?

    // Banner
    @State private var bannerPickerItem: PhotosPickerItem?
    @State private var bannerImageData: Data?
    @State private var removeBanner = false
    @State private var currentBannerBlob: UploadedBlob?
    @State private var currentBannerURL: URL?

    // Loading / Error
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    avatarSection
                    bannerSection
                    textFieldsSection
                    saveSection
                }
            }
            .pageTitle(loc("profile.edit.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(loc("profile.edit.error"), isPresented: $showError) {
                Button(loc("actions.ok")) { showError = false }
            } message: {
                Text(errorMessage ?? "")
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text(loc("profile.edit.saving"))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                }
            }
        }
        .task {
            await loadCurrentRecord()
        }
    }

    // MARK: - Sections

    @MainActor
    private var avatarSection: some View {
        let avatarChangeLabel = loc("profile.edit.avatar.change")
        return Section {
            VStack(alignment: .center, spacing: 12) {
                // Preview
                Group {
                    if removeAvatar {
                        avatarPlaceholder(size: 96)
                    } else if let avatarImageData,
                              let uiImage = UIImage(data: avatarImageData)
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else if let avatarURL = account.avatarURL ?? accountStore.activeAccount?.avatarURL {
                        ThumbnailImageView(url: avatarURL, maxPixelSize: 192) {
                            avatarPlaceholder(size: 96)
                        }
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder(size: 96)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }

                Text(loc("profile.edit.avatar.label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    PhotosPicker(
                        selection: $avatarPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(avatarChangeLabel, systemImage: "photo")
                            .font(.subheadline)
                    }
                    .onChange(of: avatarPickerItem) { _, newItem in
                        Task { await loadAvatar(from: newItem) }
                    }

                    if currentAvatarBlob != nil || avatarImageData != nil, !removeAvatar {
                        Button(role: .destructive) {
                            removeAvatar = true
                            avatarImageData = nil
                        } label: {
                            Label(loc("profile.edit.avatar.remove"), systemImage: "trash")
                                .font(.subheadline)
                        }
                    }

                    if removeAvatar {
                        Button(loc("actions.cancel")) {
                            removeAvatar = false
                        }
                        .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private var bannerSection: some View {
        let bannerChangeLabel = loc("profile.edit.banner.change")
        return Section {
            VStack(alignment: .center, spacing: 12) {
                // Preview
                Group {
                    if removeBanner {
                        bannerPlaceholder
                    } else if let bannerImageData,
                              let uiImage = UIImage(data: bannerImageData)
                    {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if let bannerURL = currentBannerURL {
                        AsyncImage(url: bannerURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                bannerPlaceholder
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        bannerPlaceholder
                    }
                }

                Text(loc("profile.edit.banner.label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    PhotosPicker(
                        selection: $bannerPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(bannerChangeLabel, systemImage: "photo")
                            .font(.subheadline)
                    }
                    .onChange(of: bannerPickerItem) { _, newItem in
                        Task { await loadBanner(from: newItem) }
                    }

                    if currentBannerBlob != nil || bannerImageData != nil, !removeBanner {
                        Button(role: .destructive) {
                            removeBanner = true
                            bannerImageData = nil
                        } label: {
                            Label(loc("profile.edit.banner.remove"), systemImage: "trash")
                                .font(.subheadline)
                        }
                    }

                    if removeBanner {
                        Button(loc("actions.cancel")) {
                            removeBanner = false
                        }
                        .font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var textFieldsSection: some View {
        Section {
            TextField(loc("profile.edit.display_name"), text: $displayName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(false)

            TextEditor(text: $description)
                .frame(minHeight: 100)
        } header: {
            Text(loc("profile.edit.text_fields"))
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await saveProfile() }
            } label: {
                HStack {
                    Spacer()
                    Text(loc("profile.edit.save"))
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Helpers

    private func avatarPlaceholder(size: CGFloat) -> some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
            }
    }

    private var bannerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .overlay {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Data Loading

    private func loadCurrentRecord() async {
        defer { isLoading = false }

        // Pre-fill text fields from account store
        displayName = account.displayName
        description = ""

        // Try to get description from a fresh profile fetch
        do {
            let profile = try await container.profile.fetchProfile(
                did: account.did ?? account.handle,
                account: account,
                appPassword: appPassword
            )
            if displayName == account.handle, profile.displayName != nil {
                displayName = profile.displayName ?? account.displayName
            }
            description = profile.description ?? ""
            currentBannerURL = profile.bannerURL
        } catch {
            AppLogger.moderation.error("Failed to fetch profile for edit: \(error.localizedDescription, privacy: .private)")
        }

        // Fetch raw profile record to get current blob refs
        do {
            if let record = try await container.blueskyClient.fetchMyProfileRecord(account: account, appPassword: appPassword) {
                currentAvatarBlob = record.avatar
                currentBannerBlob = record.banner
            }
        } catch {
            // Record may not exist yet (new accounts); that's fine
            AppLogger.moderation.debug("No existing profile record: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            avatarImageData = data
            removeAvatar = false
        }
    }

    private func loadBanner(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            bannerImageData = data
            removeBanner = false
        }
    }

    // MARK: - Save

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            // 1. Upload new avatar if changed
            var avatarBlob: UploadedBlob?
            if let data = avatarImageData {
                let response = try await container.media.uploadBlob(
                    data: data,
                    mimeType: "image/jpeg",
                    account: account,
                    appPassword: appPassword,
                    progress: nil
                )
                avatarBlob = response.blob
            } else if removeAvatar {
                avatarBlob = nil // Will be nil in the record → avatar cleared
            } else {
                avatarBlob = currentAvatarBlob // Keep current
            }

            // 2. Upload new banner if changed
            var bannerBlob: UploadedBlob?
            if let data = bannerImageData {
                let response = try await container.media.uploadBlob(
                    data: data,
                    mimeType: "image/jpeg",
                    account: account,
                    appPassword: appPassword,
                    progress: nil
                )
                bannerBlob = response.blob
            } else if removeBanner {
                bannerBlob = nil // Will be nil in the record → banner cleared
            } else {
                bannerBlob = currentBannerBlob // Keep current
            }

            // 3. Build the complete profile record
            let record = ProfileRecord(
                displayName: displayName.nilIfBlank,
                description: description.nilIfBlank,
                avatar: avatarBlob,
                banner: bannerBlob,
                createdAt: ISO8601DateFormatter().string(from: .now)
            )

            // 4. Write the record
            try await container.profile.putProfileRecord(record, account: account, appPassword: appPassword)

            // 5. Refresh account store profile data
            await accountStore.refreshAccountProfiles(using: container.blueskyClient)

            dismiss()
        } catch {
            errorMessage = AppError.userMessage(from: error)
            showError = true
            AppLogger.moderation.error("Profile save failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
