#!/usr/bin/env python3
"""Final comprehensive pass: fix ALL remaining blueskyClient references in view files.

This includes:
1. Files missed from the initial 48 (PostLikerActionsViewModifier, extension files)
2. Remaining end-of-line patterns (using: blueskyClient)
3. Other patterns like client: blueskyClient, blueskyClient.createPost, etc.
"""

import re
import os

BASE = "/Users/ajung/src/RULYX"

# All files we need to process - the original 48 + missed files
FILES = [
    # Original 48
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
    # Missed files with @EnvironmentObject
    "Sources/Shared/Components/Posts/PostLikerActionsViewModifier.swift",
    # Extension files that reference blueskyClient from parent types
    "Sources/Features/Lists/ListDetailView+Helpers.swift",
    "Sources/Features/Lists/ListsView+Export.swift",
]

def process_file(filepath):
    full_path = os.path.join(BASE, filepath)
    
    if not os.path.exists(full_path):
        print(f"  SKIP (not found): {filepath}")
        return False
    
    with open(full_path, 'r') as f:
        content = f.read()
    
    original = content
    
    # Step 1: Replace @EnvironmentObject declaration (for missed files)
    content = re.sub(
        r'@EnvironmentObject(\s+private)?\s+var\s+blueskyClient:\s*LiveBlueskyClient',
        r'@EnvironmentObject\1 var container: BlueskyServiceContainerWrapper',
        content
    )
    
    # Step 2: Replace blueskyClient. -> container.blueskyClient.
    content = content.replace('blueskyClient.', 'container.blueskyClient.')
    
    # Step 3: Replace blueskyClient) -> container.blueskyClient)
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
        r'=\s*blueskyClient\b',
        r'= container.blueskyClient',
        content
    )
    
    # Step 6: Replace 'using: blueskyClient' at end of line
    content = re.sub(
        r'using:\s*blueskyClient(\s*)$',
        r'using: container.blueskyClient\1',
        content,
        flags=re.MULTILINE
    )
    
    # Step 7: Replace 'client: blueskyClient' at end of line  
    content = re.sub(
        r'client:\s*blueskyClient(\s*)$',
        r'client: container.blueskyClient\1',
        content,
        flags=re.MULTILINE
    )
    
    # Step 8: Replace any remaining bare 'blueskyClient' at end of line
    # (that isn't already container.blueskyClient, deps.blueskyClient, etc.)
    content = re.sub(
        r'(?<!container\.)(?<!deps\.)blueskyClient(\s*)$',
        r'container.blueskyClient\1',
        content,
        flags=re.MULTILINE
    )
    
    if content != original:
        with open(full_path, 'w') as f:
            f.write(content)
        # Count changes
        changes = sum(1 for a, b in zip(original.split('\n'), content.split('\n')) if a != b)
        print(f"✓ Modified ({changes} lines): {filepath}")
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
