/// Top level destinations of the dashboard navigation bar.
enum Menu {
  /// Conversation list.
  chats,

  /// Communities this identity belongs to, with their channels.
  communities,

  /// People this identity knows, grouped by trust.
  trustees,

  /// Who is connected to your node, the Tor relays carrying your traffic and
  /// the bridges used to reach Tor.
  network,

  /// Profile, preferences and vault security.
  settings,
}

/// Quick filters shown above the conversation list.
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

/// Quick filters available for peer listings.
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

/// Categories of search results on the offline network map.
enum Types { all, email, username }

/// Delivery lifecycle of a message. Persisted by index, so only append.
enum Status {
  /// Queued locally, not yet written to a peer.
  sending,

  /// Written to the peer's onion service, awaiting acknowledgement.
  sent,

  /// The peer acknowledged and stored the message.
  delivered,

  /// The peer opened the conversation and saw the message.
  read,
}

/// Visual style of the offline network map.
enum Appearance { light, dark, grayscale }

/// Connectivity of the embedded Tor daemon as seen by the courier.
enum Reach {
  /// Tor is down or failed to bootstrap; retries run in the background.
  offline,

  /// Tor is bootstrapping circuits.
  connecting,

  /// Tor is bootstrapped and the onion service is reachable.
  online,
}

/// How far a peer is trusted. Persisted by index, so only append.
enum Trust {
  /// An unknown sender whose request has not been answered yet.
  stranger('Request'),

  /// Someone you chose to trust. Only trustees see your profile.
  trustee('Trustee'),

  /// Everything from this address is silently dropped.
  blocked('Blocked');

  const Trust(this.label);
  final String label;
}

/// Availability advertised to trustees. Persisted by index, so only append.
enum Availability {
  /// Reachable and happy to chat.
  available('Available', 'Reachable and happy to chat'),

  /// Around, but replies may be slow.
  away('Away', 'Around, but replies may be slow'),

  /// Do not disturb: in-app banners are muted on this device.
  busy('Do not disturb', 'Mutes in-app banners on this phone'),

  /// Appear offline: no pongs, typing hints or read receipts are sent.
  invisible('Invisible', 'Appear offline to everyone');

  const Availability(this.label, this.hint);
  final String label;
  final String hint;
}

/// Payload carried by a message. Persisted by index, so only append.
enum Kind {
  /// Plain text.
  text,

  /// A photo, stored encrypted on this device.
  image,

  /// An animated GIF, usually picked from GIPHY.
  gif,

  /// Any other file, stored encrypted on this device.
  file,

  /// A shared trustee (onion address and display name).
  card,

  /// An invitation to a community, carrying its key.
  invite,

  /// A recorded voice message, stored encrypted on this device.
  voice,

  /// A video clip, stored encrypted on this device.
  video,
}

/// What a community post is. Persisted by index, so only append.
enum Note {
  /// A message in a channel.
  text,

  /// A member introducing themselves on joining.
  join,

  /// A new channel.
  channel,

  /// A new name, description, icon or banner for the community.
  about,

  /// A podcast episode; its audio is fetched in pieces from members.
  episode,

  /// A vote to remove a member, or to take that vote back.
  vote,
}

/// The kinds of channel a community can have. Persisted by name.
enum Space {
  text('Text', '#'),
  podcast('Podcast', ''),
  voice('Voice', '');

  const Space(this.label, this.mark);
  final String label;
  final String mark;
}

/// Frame types spoken over the onion wire protocol.
enum Signal {
  /// Announces the sender's profile revision when a channel opens.
  hello,

  /// Requests the full profile of the receiver.
  whois,

  /// Carries name, bio, status, availability and picture.
  profile,

  /// A text or trustee card message.
  message,

  /// Manifest that precedes the chunks of an attachment.
  file,

  /// Unsigned slice of an attachment, verified by the manifest hash.
  chunk,

  /// Acknowledges that a message or attachment was stored.
  receipt,

  /// Lists message ids the receiver has seen.
  read,

  /// The sender is composing a message.
  typing,

  /// Latency probe.
  ping,

  /// Answer to a latency probe.
  pong,

  /// Sets the disappearing message timer for both sides of a chat.
  timer,

  /// Carries the profile banner, too large to share the profile frame.
  banner,

  /// Exchanges encryption bundles and opens end-to-end sessions.
  session,

  /// Community posts and the sync that passes them between members.
  mesh,
}

/// How long messages last before both phones delete them.
enum Fuse {
  off(0, 'Off'),
  minutes(300, '5 minutes'),
  hour(3600, '1 hour'),
  day(86400, '1 day'),
  week(604800, '1 week');

  const Fuse(this.seconds, this.label);
  final int seconds;
  final String label;

  /// Longest timer a peer may ask for.
  static const int ceiling = 4 * 604800;

  /// The closest choice to a timer set on the other phone.
  static Fuse of(int seconds) => values.lastWhere(
    (item) => item.seconds <= seconds,
    orElse: () => Fuse.off,
  );
}

/// Highest GIPHY content rating allowed in the GIF picker.
enum Rating {
  g('g', 'G'),
  pg('pg', 'PG'),
  pg13('pg-13', 'PG-13'),
  r('r', 'R');

  const Rating(this.code, this.label);
  final String code;
  final String label;
}
