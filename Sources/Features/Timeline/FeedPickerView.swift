import SwiftUI

struct FeedPickerView: View {
    @ObservedObject var feedStore: FeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var feedURIInput = ""
    @State private var feedNameInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        feedStore.resetToFollowing()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                                .opacity(!feedStore.isUsingCustomFeed ? 1 : 0)
                            VStack(alignment: .leading) {
                                Text(loc("timeline.following"))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: loc("timeline.picker_default"))
                }

                Section {
                    TextField(loc("timeline.feed_uri_placeholder"), text: $feedURIInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.caption.monospaced())
                    TextField(loc("timeline.feed_name_placeholder"), text: $feedNameInput)
                    Button {
                        guard !feedURIInput.isEmpty else { return }
                        let name = feedNameInput.isEmpty ? loc("timeline.custom_feed") : feedNameInput
                        feedStore.setFeed(uri: feedURIInput, name: name)
                        dismiss()
                    } label: {
                        Text(verbatim: loc("timeline.picker_apply"))
                    }
                    .disabled(feedURIInput.isEmpty)
                } header: {
                    Text(verbatim: loc("timeline.picker_custom"))
                }

                if !feedStore.recentFeeds.isEmpty {
                    Section {
                        ForEach(feedStore.recentFeeds, id: \.uri) { recent in
                            Button {
                                feedStore.setFeed(uri: recent.uri, name: recent.name)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(recent.name)
                                            .foregroundStyle(.primary)
                                        Text(recent.uri)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if feedStore.customFeedURI == recent.uri {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.skyPrimary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: loc("timeline.picker_recent"))
                    }
                }

                if feedStore.isUsingCustomFeed {
                    Section {
                        HStack {
                            Text(loc("timeline.current_feed"))
                            Spacer()
                            Text(feedStore.customFeedName)
                                .foregroundStyle(.secondary)
                        }
                        Text(feedStore.customFeedURI ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle(loc("timeline.picker_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
            }
        }
    }
}
