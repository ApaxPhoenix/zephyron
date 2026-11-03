# Changelog

Every release of Zephyron, newest first. Each version's full notes, with what
works and what doesn't yet, are in [`releases/`](releases) and on the
[Releases](https://github.com/ApaxPhoenix/zephyron/releases) page. Versions
with a hyphen, like `0.3.0-beta.2`, are pre-releases.

## [0.3.0] - 2026-11-02

### Added
- Scanning a trustee's code with a phone's camera opens Zephyron with their address filled in
- App icon shortcuts to add a trustee, show your code, lock the vault or start a panic wipe

### Fixed
- Reopening the app after leaving it with Back no longer crashes it; the Tor already running in the process is reused
- Scanned zephyron:// codes open the app instead of failing as an unknown protocol
- The Windows installers no longer carry WiX's debug data

## [0.3.0-beta.2] - 2026-10-18

### Added
- Packages for Android, iOS, macOS, and Windows and Linux on x64 and ARM64, built and released by GitHub Actions with checksums
- `VERSION` and hand-written notes for each release

## [0.3.0-beta.1] - 2026-09-20

### Added
- A locked phone stays reachable and keeps what arrives sealed until the next unlock
- Notifications that only say who wrote and how many messages
- Chats, requests and trustees in one tab
- Our own code for photos, files, sharing, QR codes and playback
- A threat model in `SECURITY.md`

### Fixed
- Onion addresses carry the SHA3-256 checksum Tor expects, so every pair of phones can reach each other
- The app reopens on the unlock page when it already has an identity
- Picked photos and files are deleted as soon as they are read

## [0.2.0] - 2026-09-06

### Added
- Voice calls with a trustee, and group calls
- Private groups next to direct chats
- The opt-in Discover directory

### Fixed
- Unlocks are watched across every identity together

## [0.2.0-beta.2] - 2026-08-23

### Added
- Trustees and mailbox phones hold sealed messages for people who are offline

## [0.2.0-beta.1] - 2026-08-16

### Added
- Peer-to-peer communities with text, podcast and live voice channels
- Voice and video messages, with thumbnails
- Removal from a community by vote, and proof of work against bots
- Post-quantum sessions with ML-KEM-768 on Android
- Traffic padded to fixed sizes

## [0.1.0] - 2026-07-05

### Added
- End-to-end encryption with the Double Ratchet
- A panic wipe and rate-limited unlocks
- Screenshots blocked, a photo cropper and freeRASP checks in release builds

## [0.1.0-beta.2] - 2026-06-21

### Added
- The courier, carrying messages between trustees over onion services
- The conversation and relays pages, and a new registration screen
- Identity stores bound to the phone's secure hardware
- A disappearing message timer and a duress passphrase

## [0.1.0-beta.1] - 2026-05-24

### Added
- Tor inside the app, with obfs4 bridges
- Sign-up and log-in with identities
- A build workflow for every platform

### Fixed
- Tor starts on every launch

## [0.1.0-alpha.2] - 2026-05-03

### Added
- The chats list and peers page
- An identity model and a Tor wrapper
- The map on the new maplibre package

### Removed
- The zstd experiment

## [0.1.0-alpha.1] - 2026-03-31

### Added
- The app's shell on Android, iOS, macOS, Linux, Windows and the web
- The network map with an offline download

[0.3.0]: https://github.com/ApaxPhoenix/zephyron/compare/v0.3.0-beta.2...v0.3.0
[0.3.0-beta.2]: https://github.com/ApaxPhoenix/zephyron/compare/v0.3.0-beta.1...v0.3.0-beta.2
[0.3.0-beta.1]: https://github.com/ApaxPhoenix/zephyron/compare/v0.2.0...v0.3.0-beta.1
[0.2.0]: https://github.com/ApaxPhoenix/zephyron/compare/v0.2.0-beta.2...v0.2.0
[0.2.0-beta.2]: https://github.com/ApaxPhoenix/zephyron/compare/v0.2.0-beta.1...v0.2.0-beta.2
[0.2.0-beta.1]: https://github.com/ApaxPhoenix/zephyron/compare/v0.1.0...v0.2.0-beta.1
[0.1.0]: https://github.com/ApaxPhoenix/zephyron/compare/v0.1.0-beta.2...v0.1.0
[0.1.0-beta.2]: https://github.com/ApaxPhoenix/zephyron/compare/v0.1.0-beta.1...v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/ApaxPhoenix/zephyron/compare/v0.1.0-alpha.2...v0.1.0-beta.1
[0.1.0-alpha.2]: https://github.com/ApaxPhoenix/zephyron/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/ApaxPhoenix/zephyron/releases/tag/v0.1.0-alpha.1
