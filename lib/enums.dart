enum Menu { chats, peers, vault }

enum ChatFilters {
  all('All'),
  unread('Unread'),
  groups('Groups'),
  direct('Direct'),
  pinned('Pinned'),
  ephemeral('Ephemeral'),
  archived('Archived');

  const ChatFilters(this.label);
  final String label;
}

enum PeerFilters {
  all('All'),
  online('Online'),
  pinned('Pinned'),
  pending('Pending'),
  authenticated('Authenticated'),
  mesh('Mesh'),
  blocked('Blocked');

  const PeerFilters(this.label);
  final String label;
}

enum Types { all, email, username }

enum Status { sending, sent, delivered, read }

enum Appearance { light, dark, grayscale }
