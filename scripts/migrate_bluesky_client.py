#!/usr/bin/env python3
"""Migrate all view files from @EnvironmentObject var blueskyClient to BlueskyServiceContainerWrapper."""

import re
import sys
import os

BASE = "/Users/ajung/src/RULYX"

# Files that have @EnvironmentObject var blueskyClient (from grep results)
# Each entry: relative path from BASE
FILES = [
    "Sources/Features/Notifications/NotificationTab.swift",
    "Sources/App/SettingsView.swift",
    "Sources/App/RootView.swift",
    "Sources/App/iPad/iPadNotificationsView.swift",
    "Sources/App/iPad/iPadListsView.swift",
    "Sources/App/iPad/iPadListDetailView.swift",
    "Sources/Features/Timeline/FeedTimelineView.swift",
    "Sources/App/iPad/iPadChatView.swift",
    "Sources/Features/Timeline/ThreadView.swift",
    "Sources/Features/Accounts/AddAccountView.swift",
    "Sources/Features/Timeline/TimelineTab.swift",
    "Sources/App/iPad/iPadTimelineView.swift",
    "Sources/App/iPad/iPadRootView.swift",
    "Sources/Features/Lists/DirectRepliesView.swift",
    "Sources/Features/Accounts/ProfileEditView.swift",
    "Sources/Features/Chat/ConversationDetailView.swift",
    "Sources/Features/Accounts/AccountTabView.swift",
    "Sources/Features/Chat/NewConversationSheet.swift",
    "Sources/Features/Lists/UserSearchSheet.swift",
    "Sources/Shared/Components/AccountSwitcherSheet.swift",
    "Sources/Features/Profile/BulkProfileLookupView.swift",
    "Sources/Features/Profile/FollowerDiffView.swift",
    "Sources/Features/Lists/ListTemplatesView.swift",
    "Sources/Features/Profile/NetworkGraphView.swift",
    "Sources/App/iPad/iPadProfileInspector.swift",
    "Sources/Features/Lists/RelationshipsView.swift",
    "Sources/Features/Lists/ListDetailSubscribeSection.swift",
    "Sources/Features/Profile/ManagePostsView.swift",
    "Sources/Features/Lists/MentionsSearchView.swift",
    "Sources/Features/Lists/CustomSearchView.swift",
    "Sources/Features/Lists/ListDetailComparisonSection.swift",
    "Sources/Features/Profile/ProfileInspectorView.swift",
    "Sources/Features/Lists/ListDetailSnapshotSection.swift",
    "Sources/Features/Lists/ListDetailView.swift",
    "Sources/Features/Lists/BlueskyProfileView.swift",
    "Sources/Features/Lists/ListTimelineView.swift",
    "Sources/Features/Lists/BatchOperationProgressView.swift",
    "Sources/Features/Lists/ListsView.swift",
    "Sources/Shared/Components/AccountQuickSwitcherSheet.swift",
    "Sources/Features/Lists/ClearskyListsView.swift",
    "Sources/Features/Lists/ListDetailMembersSection.swift",
    "Sources/Shared/Components/LikesListView.swift",
    "Sources/Features/Lists/ListDetailSearchSection.swift",
    "Sources/Features/Lists/TrendDetectionView.swift",
    "Sources/Features/Lists/Profile/UserPostsView.swift",
    "Sources/Features/Lists/ModerationSplitView.swift",
    "Sources/Features/Lists/AutoBlockListPickerView.swift",
    "Sources/Features/Lists/Profile/MediaBrowserView.swift",
]

# RULYXApp.swift needs special handling (only remove one line, keep standalone views)
# We'll handle it separately

def process_file(filepath):
    """Process a single file, replacing @EnvironmentObject and blueskyClient references."""
    full_path = os.path.join(BASE, filepath)
    
    with open(full_path, 'r') as f:
        content = f.read()
    
    original = content
    
    # Step 1: Replace @EnvironmentObject declaration (with optional 'private')
    # @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    # @EnvironmentObject var blueskyClient: LiveBlueskyClient
    content = re.sub(
        r'@EnvironmentObject(\s+private)?\s+var\s+blueskyClient:\s*LiveBlueskyClient',
        r'@EnvironmentObject\1 var container: BlueskyServiceContainerWrapper',
        content
    )
    
    # Step 2: Replace blueskyClient. -> container.blueskyClient.
    # Only in lines that are NOT the @EnvironmentObject declaration
    content = content.replace('blueskyClient.', 'container.blueskyClient.')
    
    # Step 3: Replace blueskyClient) -> container.blueskyClient)
    # But be careful: this would also match container.blueskyClient) if it existed
    # So we need to not double-replace. Use a regex with a negative lookbehind for 'container.'
    # Since we just did Step 2, any 'blueskyClient)' would not have 'container.' before it
    # (because Step 2 only matched 'blueskyClient.' not 'blueskyClient)')
    content = re.sub(
        r'(?<!container\.)blueskyClient\)',
        r'container.blueskyClient)',
        content
    )
    
    # Step 4: Replace blueskyClient, -> container.blueskyClient,
    content = re.sub(
        r'(?<!container\.)blueskyClient,',
        r'container.blueskyClient,',
        content
    )
    
    # Step 5: Replace = blueskyClient -> = container.blueskyClient
    content = re.sub(
        r'=\s*blueskyClient\b(?!\.)',
        r'= container.blueskyClient',
        content
    )
    
    if content != original:
        with open(full_path, 'w') as f:
            f.write(content)
        print(f"✓ Modified: {filepath}")
        return True
    else:
        print(f"  No changes: {filepath}")
        return False

def main():
    modified_count = 0
    for filepath in FILES:
        if process_file(filepath):
            modified_count += 1
    
    print(f"\nTotal files modified: {modified_count}/{len(FILES)}")

if __name__ == '__main__':
    main()
