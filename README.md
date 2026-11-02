# Zephyron

**Private, peer-to-peer messaging over Tor. No servers, no phone numbers, no accounts.**

Zephyron is a chat app where you own your identity outright. There is no
company server holding your messages, no sign-up with an email or phone number,
and nothing linking who you are to who you talk to. Your identity is a key that
lives on your phone, your address is a Tor onion address, and messages travel
directly from one device to another through the Tor network.

Zephyron is built by the people, for the people, regardless of who they are or
where they are. Everyone deserves the right to privacy.

> **Status: early development.** Zephyron runs on Android today and is changing
> quickly. It has not been independently audited, so please don't rely on it
> where your safety depends on it yet.

## What it's going to be

- **A messenger nobody can switch off.** With no central server there is
  nothing to shut down, block or subpoena. If two phones can reach Tor, they
  can talk.
- **Private by default, not by setting.** No contact list upload, no metadata
  stored by a provider, no analytics. Only the people you trust ever see your
  profile.
- **Yours to keep.** A 12-word recovery phrase is all you need to bring your
  identity to a new device. Lose it, and nobody (including us) can get it back
  or take it from you.
- **Works when the internet doesn't.** The goal is messaging and maps that keep
  working off-grid: offline maps today, and mesh links over USB and serial
  radios next.

## How it works

1. **Your identity is a key.** When you create an identity, Zephyron generates
   a 12-word recovery phrase (BIP-39) and derives an Ed25519 key pair from it.
   The public key *is* your address: a 56-character Tor v3 `.onion` address.
2. **Your phone is the server.** Zephyron runs Tor inside the app and publishes
   your address as an onion service. Friends connect straight to it, and Tor
   hides both of your IP addresses from each other and from everyone in between.
3. **Every message is signed and end-to-end encrypted.** Messages are sent
   with the `zephyron/1` wire protocol. Each frame is signed with your key, so
   peers can tell it really came from you. Messages and files are encrypted
   with the Double Ratchet, and sessions open with X3DH plus ML-KEM-768, so
   recorded traffic stays safe even from a future quantum computer. All of it
   travels inside Tor's onion-service encryption too.
4. **Size and timing give little away.** Encrypted traffic is padded to fixed
   size classes and sent after a short random delay.
5. **Everything at rest is encrypted.** Your identity, contacts and messages
   are stored in a SQLCipher database whose key is derived from your passphrase
   with Argon2id, mixed with a secret kept in your phone's secure hardware. A
   copy of the database taken off the phone can't be brute forced elsewhere.
   Photos and files are stored encrypted on the device too.

## Features

**Identity and security**
- Create several identities on one device, each with its own recovery phrase
  and passphrase.
- The app locks itself after 10 minutes without use.
- Wrong passphrases are rate limited: 5 within 15 minutes locks the identity
  for a while, and the lockout doubles each time up to an hour. After 10 wrong
  passphrases in a row the identity is erased from the device.
- Failed unlocks are also watched across every identity together. 6 failures
  within 15 minutes lock all of them, and patterns that look like an attack
  (rotating identities, trying one passphrase on many, scripted speed, a
  wound-back clock) erase every identity on the phone.
- A duress passphrase opens a harmless decoy identity and quietly erases the
  rest.
- A panic wipe erases everything after a five-second countdown. Start it from
  Settings, by long-pressing the unlock screen's title, or from the app icon's
  shortcut.
- Screenshots and screen recording are blocked, and chats are hidden in the
  app switcher.
- Release builds check for root, hooking frameworks, emulators and tampering
  with [freeRASP](https://github.com/talsec/Free-RASP-Flutter). Serious
  tampering erases every identity, and lighter warnings lock the vault.

**Chats**
- Text, photos, files up to 25 MB, GIFs and shared contact cards.
- Voice messages up to 10 minutes, and video messages with a thumbnail.
- Disappearing messages: 5 minutes, 1 hour, 1 day or 1 week per chat.
- Voice calls with a trustee, and group calls.
- Private groups: small invite-only chats that sit next to your direct chats.
- Messages still arrive when someone is offline. A trustee, or a mailbox phone
  you choose, holds them sealed until the recipient is back.
- Delivery states: sending, sent, delivered and read.
- Typing indicators, read receipts and in-app banners, each of which can be
  turned off.
- Pin, archive and search conversations.
- GIF search goes through Tor too, so GIPHY never sees your IP address.

**Communities**
- Peer-to-peer communities with no server and no owner, with text, podcast
  and live voice channels.
- Podcast episodes up to an hour or 50 MB, shared between members.
- Voice rooms for up to six people.
- Members can vote someone out. Once more than half agree, the community key
  changes so the removed person can't read anything new.
- Proof of work on joining and per-member rate limits keep bots out.

**People**
- Requests from strangers stay separate until you accept them.
- Trustees see your profile; blocked addresses are silently dropped.
- Safety codes let you confirm, in person or over another channel, that you
  are talking to the right key.
- Profile photos with a cropper, and a banner image or GIF.
- An opt-in Discover directory where people and communities can choose to be
  listed, shared between phones with no server.
- Set your availability: available, away, do not disturb or invisible. Do not
  disturb also turns calls away.

**Network**
- See who is connected to your node and the Tor circuits and relays carrying
  your traffic.
- Use obfs4 bridges to reach Tor where it is blocked.
- An offline map with location search, downloaded once and usable without a
  connection.

## How it compares

|  | Zephyron | Signal | Session | Briar | SimpleX |
| --- | :---: | :---: | :---: | :---: | :---: |
| No phone number or email | ✅ | ❌ | ✅ | ✅ | ✅ |
| No servers at all, phone to phone | ✅ | ❌ | ❌ | ✅ | ❌ |
| Hides your IP address | ✅ Tor | ❌ | ✅ | ✅ Tor | Optional |
| End-to-end encrypted by default | ✅ | ✅ | ✅ | ✅ | ✅ |
| Post-quantum encryption | ✅ | ✅ | ❌ | ❌ | ✅ |
| Voice calls | ✅ | ✅ | ✅ | ❌ | ✅ |
| Group calls | ✅ | ✅ | ❌ | ❌ | ❌ |
| Communities with channels | ✅ | ❌ | ❌ | ❌ | ❌ |
| Messages reach you while offline | ✅ | ✅ | ✅ | ✅ | ✅ |
| Works without internet | Planned | ❌ | ❌ | ✅ | ❌ |
| Offline maps | ✅ | ❌ | ❌ | ❌ | ❌ |

Zephyron also has things none of these do together: a duress passphrase that
opens a decoy identity, a device-wide guard against passphrase guessing, keys
bound to the phone's secure hardware, and a server-free Discover directory.

This table is our best reading of each app's public documentation and may
fall out of date. If something is wrong, please open an issue.

## Roadmap

**Next**
- Mesh messaging over USB and serial radios, for when there's no internet
- Tor on iOS, macOS, Windows and Linux (the apps build there today, but Tor
  currently only runs on Android)
- Post-quantum sessions on iOS (they fall back to classical encryption there
  until liboqs is built for it)
- Signed builds for every platform on the Releases page

**Later**
- Video calls
- Using one identity on several of your own devices
- Moving an identity and its chats to a new phone, not just the identity
- Message reactions, replies and edits
- Reproducible builds, so anyone can check a release matches the source
- An independent security audit

## Platforms

| Platform | Status |
| --- | --- |
| Android | Works. This is where development happens. |
| iOS | Builds, Tor not supported yet. |
| macOS, Windows, Linux | Build, Tor not supported yet. |

When a version is released, builds for every platform will be published on
the [Releases](https://github.com/ApaxPhoenix/zephyron/releases) page.

## Building from source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.44.2 or
newer, the Android SDK and Java 17 or newer.

```bash
git clone https://github.com/ApaxPhoenix/zephyron.git
cd zephyron
flutter pub get
flutter run
```

### Configuration

Optional services are configured at build time. Copy `.env.example` to `.env`,
fill in what you need and pass it to Flutter with `--dart-define-from-file=.env`.

| Key | What it's for |
| --- | --- |
| `GIPHY_API_KEY` | GIF search in chats |
| `CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Downloading offline map data |
| `APP_CERT_HASH` | Base64 SHA-256 of your signing certificate, used by freeRASP |

Never commit `.env`. Anything passed with `--dart-define` is compiled into the
app, so don't ship builds containing keys you can't afford to have extracted.

### Release builds

To sign with your own key, create `android/key.properties`:

```properties
storeFile=/path/to/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Then build:

```bash
flutter build apk --release --dart-define-from-file=.env
```

If `APP_CERT_HASH` is set, freeRASP closes the app when the signing certificate
doesn't match it, so make sure it is the hash of the key in `key.properties`.
Without `APP_CERT_HASH`, runtime threat detection is turned off for that build.

`scripts/oqs.sh` rebuilds the bundled liboqs libraries from source if you want
to check or update them.

### Tests

```bash
flutter test
```

## Security

Found a vulnerability? Please email
[security@aveloux.com](mailto:security@aveloux.com) and read
[SECURITY.md](SECURITY.md) before disclosing anything publicly.

## Contributing

Contributions of every size are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md), and please read the
[Code of Conduct](CODE_OF_CONDUCT.md) and our [Rules](RULES.md). Questions are
welcome on [Discord](https://discord.gg/GSeTUeA) or in an issue.

## License

Zephyron is free software, licensed under the
[GNU Affero General Public License v3.0](LICENSE). You can use, study, share
and change it, and if you distribute it or run a modified version for others
over a network, you must share your source code under the same license.
