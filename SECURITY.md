# Security

Contact: [security@aveloux.com](mailto:security@aveloux.com)

We consider the security of our systems a top priority. But no matter
how much effort we put into system security, there can still be vulnerabilities
present. Code is generally unsafe even when all precautions are taken, and we
sincerely ask for your help.

If you discover a vulnerability, we would like to know about it so we can take
steps to address it as quickly as possible. We would like to ask you to help us
better protect our clients and our systems.

The [threat model](#threat-model) at the end says what Zephyron is built
to withstand and where that protection stops.

## Out of scope vulnerabilities

* Attacks requiring physical access to a user's device.
* Attacks requiring a fully compromised endpoint.
* Denial-of-service and resource exhaustion attacks.
* Social engineering or phishing attacks.
* Attacks against third-party services or infrastructure.
* Traffic analysis by a global passive adversary.
* Attacks requiring control of a user's ISP or network.
* User self-deanonymization or voluntarily disclosed information.
* Vulnerabilities caused solely by outdated third-party software.
* Spam, abuse, or malicious content sent through the network.
* Theoretical attacks without a practical proof of concept.
* Issues requiring unrealistic or highly privileged access.

## Please do the following

* E-mail your findings to [security@aveloux.com](mailto:security@aveloux.com).
* Do not take advantage of the vulnerability or problem you have discovered,
  for example, by downloading more data than necessary to demonstrate the
  vulnerability or deleting or modifying other people's data. We are doing
  this project for the greater good of humanity.
* Do not reveal the problem to others until it has been resolved.
* Do not use attacks on physical security, social engineering, distributed
  denial of service, spam, or applications of third parties.
* Do provide sufficient information to reproduce the problem, so we will be
  able to resolve it as quickly as possible. Usually, the IP address or the URL
  of the affected system and a description of the vulnerability will be
  sufficient, but complex vulnerabilities may require further explanation.

## What we promise

* We will respond to your report within 3 business days with our evaluation of
  the report and an expected resolution date.
* If you have followed the instructions above, we will not take any legal
  action against you in regard to the report.
* We will handle your report with strict confidentiality and not pass on your
  personal details to third parties without your permission.
* We will keep you informed of the progress towards resolving the problem.
* In the public information concerning the problem reported, we will give your
  name as the discoverer of the problem (unless you desire otherwise).
* We strive to resolve all problems as quickly as possible, and we would like
  to play an active role in the ultimate publication on the problem after it
  is resolved.
* If all measures fail, contact us through social media, and we will provide a
  direct phone line to our security team.

## Threat model

This section says what Zephyron is built to protect, who it protects it
from, and where that protection stops. It describes the Android and iOS
apps, the platforms where Tor runs today, and says where iOS differs.
Zephyron has not had an independent audit yet.

### What it protects

* **What you say:** messages, photos, files, voice and video messages, calls,
  and community posts.
* **Where you are:** your IP address, which your contacts never see.
* **Who you are:** your identity's key, which never leaves your phone.
* **What is on your phone:** your identities, contacts and chat history.

### Anyone watching the network

Your internet provider, the Wi-Fi you're on, or anyone else on the path sees
only Tor traffic. They can't see who you talk to or what you say. Where Tor
itself is blocked or watched, obfs4 bridges hide the fact that you use it.

### Everyone in between

There are no Zephyron servers. Messages go from your phone's onion service to
the other phone's, so the only things in between are Tor relays.

* Every frame is signed with the sender's key. Your address is your public
  key, so nobody can pose as an address without holding its key.
* Messages and files are end-to-end encrypted with the Double Ratchet, so a
  key stolen later can't open older messages. After a key is stolen, the
  session heals itself once both sides have sent new messages.
* Encrypted messages are padded to fixed size classes (256 bytes, 512 bytes
  and up), and attachments travel in chunks of one width. Each send waits a
  random 150 to 1200 ms. Size and timing tell an observer less.

### Recording now to decrypt later

New sessions combine X25519 with ML-KEM-768 from the bundled liboqs. Traffic
recorded today stays sealed even if a future quantum computer breaks X25519.

Some things are still classical:

* Frame signatures use Ed25519. Forging one would take a quantum computer
  working in real time; recorded traffic doesn't help.
* Tor's own encryption is classical.
* On iOS, sessions fall back to classical until liboqs is built for it.

The profile page of each trustee shows whether your session is post-quantum.

### The people you talk to

Trustees see your profile and what you send them. They also see when you're
online, unless you set yourself to invisible. Zephyron can't stop them saving
or forwarding what you send. Blocking screenshots only works on your own
phone. Safety codes let you check, in person or over another channel, that a
trustee's key is the one you meant.

When someone is offline, a trustee or a mailbox phone you chose holds your
messages until they're back. It can't read them. It does learn who wrote to
whom, when, and how many messages were sent. A phone holds at most 200
messages from one sender and 2,000 in all, and drops anything older than
7 days.

### A locked phone

Locking closes the encrypted store, but your address stays online so people
can still reach you. A foreground service with a quiet "Ready to receive
messages" notification keeps Android from stopping the app, and with it Tor.

* What arrives while locked is sealed again on arrival, to a holding key: an
  X25519 key pair whose private half lives inside the encrypted store, so it
  can only be opened after the next unlock. Each frame is sealed with a fresh
  ephemeral key, HKDF and AES-GCM. The file it is kept in is named by a hash
  of your address, not the address itself.
* Only signed frames addressed to the locked identity are held: messages,
  receipts, read notices and timer changes. A phone holds at most 500 frames,
  100 from any one sender and none larger than 64 KB, and drops the rest.
* The phone tells the sender it kept a message, so the sender stops retrying.
  That answer is unsigned, because the signing key is locked away, so a phone
  only believes it on a connection it dialed itself, where Tor has already
  proven who is on the other end.
* Panic wipes and erased identities take the held frames with them.

iOS has no such service: it suspends an app soon after it leaves the screen,
and Tor with it. An iPhone is reachable only while Zephyron is open, and what
is sent to it meanwhile waits on the sender's phone or with a trustee who
holds it.

### Notifications

Notifications go through the phone's own notification manager. They say who
wrote and how many messages there are, never what the messages say. While
the phone is locked they don't name the sender either, since the sender is
sealed away too, and the lock screen shows only "New messages". Do not
disturb and turning banners off silence them.

### Strangers, spam and bots

Strangers can't reach your chats. Unless you turn message requests off, what
they send waits in a separate list until you accept it. Only trustees can call
you, and only trustees can pass you Discover listings.

Joining a community takes proof of work, a few seconds of hashing on a phone,
so mass joins get expensive. New members can't vote until they have been in
the community for an hour, and anything past 30 posts a minute from one member
is dropped.

### Community and group members

Everyone in a community or group holds its key. They can read everything
posted, including the history from before they joined. They can also see one
another's addresses. More than half of the seasoned members can vote someone
out. The key then changes, so the removed person can't read anything new,
though they keep whatever they already had.

Voice rooms and group calls are sealed with a key derived from the community
key. Any member can listen in, and members can see who is on a call.

A direct call's key is made fresh for each call and sent inside your
end-to-end session, so only the person you call can listen.

### Discover

Nothing is listed unless you ask. A listing is public to every phone it
reaches: your name, bio, picture and address for a person, and a community's
name, description, picture and keys. A listed community is effectively
public, and anyone who finds it can join and read it.

Listings are signed, cost proof of work, and lapse after 14 days unless they
are renewed. One person can list at most 5 communities. Taking a listing down
sends a signed notice that replaces it on every phone. Hiding a listing stops
your phone passing it on, and you can turn off passing listings along
entirely.

### Someone holding your phone

* **Storage.** Identities, contacts and messages are kept in a SQLCipher
  database. Its key comes from your passphrase through Argon2id, mixed with
  a secret held in your phone's secure hardware, so a copy of the database
  can't be brute forced somewhere else. Photos and files are encrypted
  separately.
* **Wrong passphrases.** Five wrong passphrases within 15 minutes lock the
  identity for a while. Ten in a row erase it. Six failures across all
  identities within 15 minutes lock every identity, and patterns that look
  like an attack erase them all.
* **Coercion.** A duress passphrase opens a decoy identity and quietly erases
  the rest. A panic wipe erases everything after a five-second countdown.
* **Everyday exposure.** The app locks after 10 minutes without use, and
  reopens on the unlock page. It blocks screenshots and screen recording,
  and hides chats in the app switcher.
* **Plain copies.** Opening or sharing an attachment leaves a decrypted copy
  in the cache until the vault locks. Picked photos and files are deleted as
  soon as they are read. Anything you share to another app leaves
  Zephyron's protection.

### Where protection stops

* **A compromised phone.** Malware or root access on an unlocked phone can
  read what Zephyron shows. Release builds watch for root, hooking and
  tampering, but that only raises the bar.
* **Global watchers.** An adversary watching both ends of the Tor network
  could still match traffic by timing. The random delays make this harder,
  not impossible.
* **The offline map.** The map downloads straight from Cloudflare R2, not
  through Tor, so Cloudflare sees your IP address when you download it.
  Storage credentials are built into the app, so anyone can extract them.
  They should only ever allow reading the public map files.
* **What you choose to share.** Listing yourself, joining a public community
  or forwarding a file makes that information public on purpose.
* **Software you rely on.** Zephyron keeps third-party packages to a short
  list, and picking, playing and sharing media is its own code. It builds
  native libraries such as liboqs from pinned source with scripts in this
  repository. Even so, a compromised dependency or toolchain could
  compromise the app. On iOS, Tor and obfs4 come prebuilt from the Guardian
  Project's Tor.framework and IPtProxy, pinned to one version each; Tor's
  download is checked against the checksum its podspec names.
* **Tor inside the app.** Tor runs inside the app's own process, and only
  once per process. When Android keeps the process alive after the app's
  screen closes, the app finds the Tor already running there by the process
  id kept beside its files, rather than starting a second one. On iOS,
  Tor.framework runs Tor on a thread of its own, and obfs4 runs inside the
  app too, since iOS starts no other programs. The app reaches Tor's control
  port over loopback there, since an iOS app's folder is too deep for a Unix
  socket's path; other apps can reach that port, but not without the cookie
  in Zephyron's own folder.

### Releases

GitHub Actions builds every release from the commit it tags, after the tests
pass, and attaches a SHA-256 checksum for every package. Android builds are
signed with the project's key, and freeRASP is given that key's own
certificate hash, so a build signed with anything else closes itself. The
iOS and macOS packages are unsigned, and releases aren't reproducible yet, so
a release can't yet be checked against the source byte for byte.
