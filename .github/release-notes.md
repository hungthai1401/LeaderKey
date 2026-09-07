Caps Lock is the trigger. Tap it and it still toggles Caps Lock, hold it and
the Leader Key panel opens and stays open after the key comes back up, hold it
together with another key and you get Hyper (⌃⌥⇧⌘).

### Installing

Unzip, drop it in `~/Applications`, open it, and grant Accessibility when it
asks. The app does nothing whatsoever without that permission, since reading
the keyboard is the entire feature. Then turn the trigger on in Settings, under
Caps Lock. It ships off, because switching it on repoints a key you already
own.

The build is signed, but with a self-signed certificate rather than an Apple
one, so it is not notarized and macOS refuses the first open. Either strip the
quarantine flag before opening it:

    xattr -d -r com.apple.quarantine "Leader Key.app"

or open it once through System Settings, Privacy and Security, Open Anyway.
Right click and Open stopped working for unnotarized apps in macOS 15.

Apple Silicon only.

### Living beside the original

The bundle id is `com.hungthai.LeaderKey` rather than upstream's, so this and a
Leader Key installed from mikker/LeaderKey.app can sit side by side without
fighting over one Accessibility entry or one set of preferences. They do share
`~/Library/Application Support/Leader Key/config.json`, which is deliberate:
one keymap, either app.

Sparkle is disabled here. Nothing publishes an appcast for this fork, so there
are no automatic updates.

### If the keyboard goes strange

The remap outlives the process. A clean quit hands Caps Lock back, but a crash
leaves it pointed at F18. This puts it back:

    hidutil property --set '{"UserKeyMapping":[]}'
