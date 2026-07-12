#!/usr/bin/env python3
"""Second pass: fix remaining 'using: blueskyClient' and other missed patterns."""

import re
import os

BASE = "/Users/ajung/src/RULYX"

# Same files as before — only process view files that were already modified
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

# Extension files that reference blueskyClient from parent types
EXTRA_FILES = [
    "Sources/Features/Lists/ListDetailView+Helpers.swift",
]

def process_file(filepath):
    full_path = os.path.join(BASE, filepath)
    
    with open(full_path, 'r') as f:
        content = f.read()
    
    original = content
    
    # Replace 'using: blueskyClient' followed by newline or whitespace-then-newline
    # This catches the end-of-line pattern that was missed
    content = re.sub(
        r'using:\s*blueskyClient(\s*)$',
        r'using: container.blueskyClient\1',
        content,
        flags=re.MULTILINE
    )
    
    # Also catch 'using: blueskyClient' followed by comma (already should be caught but be safe)
    content = re.sub(
        r'using:\s*blueskyClient,',
        r'using: container.blueskyClient,',
        content
    )
    
    # Catch any remaining bare 'blueskyClient' that's NOT preceded by 'container.' or 'deps.' or 'let ' or 'var '
    # and IS at end of line (followed by optional whitespace and newline)
    # This catches patterns like:
    #   someFunc(blueskyClient
    #   )
    # But we must be careful with 'let blueskyClient: LiveBlueskyClient'
    content = re.sub(
        r'(?<!container\.)(?<!deps\.)(?<!\blet\s)(?<!\bvar\s)blueskyClient(\s*)$',
        r'container.blueskyClient\1',
        content,
        flags=re.MULTILINE
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
    all_files = FILES + EXTRA_FILES
    modified_count = 0
    for filepath in all_files:
        if process_file(filepath):
            modified_count += 1
    
    print(f"\nTotal files modified (2nd pass): {modified_count}/{len(all_files)}")

if __name__ == '__main__':
    main()
