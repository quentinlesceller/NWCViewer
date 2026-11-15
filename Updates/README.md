# Update feed

`appcast.xml` is a signed Sparkle feed, served from this directory on GitHub main.
Do not edit its bytes by hand after signing. Generate it with `Tools/prepare-update.sh`.
Upload the notarized update archive and matching source to the public release before
committing the new feed. See RELEASE.md. The private EdDSA key is only in the local Keychain.
