# Sign and share NWC Viewer

This process runs on **your Mac**, with Xcode 15+ and an Apple Developer Program membership. It produces a universal app for Intel and Apple silicon, signed with Developer ID, notarized by Apple and stapled for offline Gatekeeper checks. Your parents need macOS 13+, but do not need Xcode, a developer account or any extra runtime.

The release script first runs the native tests and stops if they fail. Fix any build/test failures before making a release.

## One-time setup

1. Install Xcode, launch it, accept its license, and select its command-line tools under Xcode Settings → Locations.
2. Add your developer account in Xcode Settings → Accounts. Create or import a **Developer ID Application** certificate with its private key into your Mac's login Keychain. An Apple Development certificate is a different certificate and cannot replace it for this release.
3. In Terminal, list available identities:

   ```sh
   security find-identity -v -p codesigning
   ```

   You should see an identity such as `Developer ID Application: Your Name (TEAMID)`.
4. Store notarization credentials in your local Keychain:

   ```sh
   xcrun notarytool store-credentials NWCViewer-notary
   ```

   Follow its prompts for your Apple ID, team ID and an **app-specific password**, created at account.apple.com. These credentials stay on your Mac. Do not paste passwords, private keys or certificates into chat or commit them to this project. An App Store Connect API key is another option supported by notarytool.

## Make the release

Unzip the latest project, open Terminal in the `NWCViewer` folder, and substitute your identity and a stable bundle identifier you control:

```sh
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='NWCViewer-notary'
export BUNDLE_ID='com.yourname.nwcviewer'
Tools/release-macos.sh
```

Apple's notarization service needs internet access and may take several minutes. A Keychain permission prompt may appear when signing; authorize your local build tools. No signing secrets are embedded in the app.

The script tests, builds both architectures, signs the helper then the app with hardened runtime and a secure timestamp, submits to Apple, requires an Accepted result, staples the ticket, and checks the final signature and Gatekeeper assessment. It creates a fresh folder under `dist/` each time. Existing releases are preserved. If any step fails, the script stops; do not share intermediate artifacts.

If Apple rejects a submission, find its ID in `dist/.../notarization.json` and retrieve the explanation:

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile NWCViewer-notary
```

## Check and send

1. Open the **signed app in the release folder**, not an older Xcode build. Open an actual score your parents use. Verify its pages, zoom, printing and PDF export against the checklist in README.md. Notarization checks Apple's security requirements; it does not verify that the app works or that a score converts correctly.
2. Send **`dist/NWCViewer-.../NWCViewer-for-family.zip`** using AirDrop, email or a download link. It includes the notarized app, short instructions, and the complete corresponding source ZIP required when sharing this GPL distribution.
3. Your parents unzip it, drag **NWC Viewer.app** into Applications, and open it. A normal “downloaded from the internet” confirmation may appear. They should not need to disable Gatekeeper or remove quarantine attributes. If macOS says the developer cannot be verified, revisit signing/notarization rather than asking them to bypass it.

Keep the bundle identifier stable for future builds and increment the version/build fields in `Resources/Info.plist` for releases. The `dist` directory is ignored by Git and is not included in the source archive.

## Use an existing Xcode account

If Xcode Settings → Apple Accounts already shows your developer account, you can
use Xcode’s own authentication for notarization. No app-specific password or
separate notarytool profile is required for this route. Private keys and account
credentials remain in your local Keychain.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TEAM_ID='TEAMID'
export BUNDLE_ID='com.yourname.nwcviewer'
Tools/release-xcode.sh
```

This runs the native tests, archives both architectures with hardened runtime,
signs nested code, uploads through Xcode for Developer ID notarization, exports
the notarized app, staples and validates it, and calls `Tools/package-release.sh`
to produce the same app/instructions/corresponding-source family ZIP. It stops on
failure and preserves logs in its release directory. The command-line profile
route above remains available.
