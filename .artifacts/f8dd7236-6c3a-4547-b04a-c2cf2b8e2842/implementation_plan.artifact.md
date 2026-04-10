# Implementation Plan - Create ChatsPage

The user wants a well-designed `ChatsPage` (referred to as `chats.dart`) for the Zephyron app. Currently, the dashboard has empty directories for its tabs, and the `DashboardScreen` is missing its page content.

## User Review Required

> [!IMPORTANT]
> The `Menu` enum in `lib/enums.dart` currently only contains `chats` and `stories`, but `DashboardScreen` navigation implies more sections (Peers, Vault, Broadcasts). I will update this enum to match the UI.

## Proposed Changes

### Core Models
#### [NEW] [chat.dart](file:///C:/Users/andro/StudioProjects/zephyron/lib/models/chat.dart)
Create a `Chat` data model to represent a conversation, including properties like `name`, `lastMessage`, `timestamp`, `unreadCount`, and `avatarUrl`.

### UI Components
#### [NEW] [index.dart](file:///C:/Users/andro/StudioProjects/zephyron/lib/dashboard/chats/index.dart)
Implement the `ChatsPage` widget.
- **Design Elements:**
  - Sticky search bar at the top.
  - Horizontal list of Filter Chips (All, Unread, Groups, etc. using the `Filters` enum).
  - A scrollable list of chat items using `ListTile` styled according to `Pallete`.
  - Floating Action Button to start a new chat.
  - Use of `SF Pro` font as defined in the theme.

### Integration
#### [MODIFY] [enums.dart](file:///C:/Users/andro/StudioProjects/zephyron/lib/enums.dart)
Update `Menu` enum to include all tabs: `chats`, `broadcasts`, `peers`, `vault`.

#### [MODIFY] [index.dart](file:///C:/Users/andro/StudioProjects/zephyron/lib/dashboard/index.dart)
Inject the `ChatsPage` (and placeholders for other pages) into the `PageView` children.

## Verification Plan

### Manual Verification
- Render the `DashboardScreen` and verify that the `ChatsPage` appears correctly as the first tab.
- Check both light and dark modes to ensure `Pallete` colors are applied correctly.
- Verify that the search bar and filter chips are visually consistent with the brand.
