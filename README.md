# NWC Viewer

A small native macOS app for opening **binary NoteWorthy Composer `.nwc` files** and reading sheet music. SwiftUI provides the window and controls; a bundled open-source converter produces MusicXML, and a local OpenSheetMusicDisplay (OSMD) installation renders it in WKWebView.

## Download for Mac

[Download NWC Viewer](https://github.com/quentinlesceller/NWCViewer/releases/download/v1.6/NWCViewer-1.6-macOS.zip)

Requires macOS 13 or later; supports Intel and Apple silicon. Unzip the download,
drag **NWC Viewer.app** into Applications, then open it. The release is Developer
ID signed and notarized by Apple. The ZIP includes instructions and corresponding
GPL source; no extra runtime or developer tools are needed.

## Automatic updates

Starting with 1.6, Sparkle checks daily, downloads signed updates, and installs them when the app quits. Use **NWC Viewer → Check for Updates…** for an immediate check, or **Settings…** to disable automatic checks/downloads. Scores never leave your Mac; GitHub receives ordinary update requests, without system profiling. Updating requires internet access; reading and printing do not. Versions 1.5 and earlier need one final manual installation of 1.6.

## Using the app

1. Launch **NWC Viewer** and click **Open NWC File…** (or press Command–O).
2. Choose the original `.nwc` file. Scroll normally with a mouse or trackpad.
3. Use the magnifying-glass buttons to zoom from 50% to 200%; use the percentage menu to choose Actual Size (100%).
4. Click **Print…** (Command–P) for the macOS print dialog, or **Save PDF…** (Shift–Command–S) to save a PDF.
5. Use **Fit Width** to fit a page to your window. You can also drag an `.nwc` file onto the app. The title area shows the page count. The compact toolbar follows macOS conventions; hover over an icon for its label, or use the File and View menus. Click the zoom percentage to choose a preset or Actual Size.

Printing and PDF export capture each rendered score page into a vector PDF with A4 portrait pages, independent of viewing zoom. Printing uses the same PDF as saving. The print dialog can select another printer/paper size and scaling. For best results use A4, 100% scaling. Files associated with the app can also be opened from Finder / Open With. This is a viewer: it does not edit, play, or save NWC scores.

## Languages

The interface, tooltips, accessibility labels, and errors are available in
**English, French, Spanish, German, and Italian**. NWC Viewer follows the Mac’s
preferred language and falls back to English when needed. To choose a language
just for this app, use macOS System Settings → General → Language & Region →
Applications, add NWC Viewer, choose the language, then reopen it. Score contents
and filenames are not translated.

Translations live in `Resources/<language>.lproj`. Each language has matching
`Localizable.strings` keys and a `Localizable.stringsdict` for plural page counts.
To add a language, copy the English folder, translate its values and plural forms,
then run `python3 Tools/generate_project.py` and `python3 Tools/test_localizations.py`.

## Build on a Mac

Requirements: **macOS 13 or later**, **Xcode 15 or later** with its macOS SDK. Xcode 16 is recommended. Xcode downloads the pinned Sparkle 2.10.1 package on the first build; subsequent builds can use its cache. No additional package manager, Java, Node, or separate converter installation is needed.

1. Open `NWCViewer.xcodeproj` in Xcode.
2. Select scheme **NWCViewer**, destination **My Mac**.
3. Press Command–R.

The C++ `nwc2xml` target builds first and is copied into `NWC Viewer.app/Contents/Helpers/nwc2xml`. Web assets and license notices are copied into the app's Resources. Local builds use ad-hoc signing (`-`), so no Apple developer team is required.

Equivalent terminal commands, from this directory:

```sh
xcodebuild -project NWCViewer.xcodeproj -scheme NWCViewer \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath DerivedData build
open 'DerivedData/Build/Products/Release/NWC Viewer.app'
```

The checked-in Xcode project is deterministic and has a shared scheme. To regenerate it after changing file lists, use Python 3 (development-only):

```sh
python3 Tools/generate_project.py
```

For a universal release add `ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO` to the build command. Distribution to other Macs requires your own Developer ID signing, hardened-runtime configuration and notarization, including signing the helper. The default local build is **not notarized** or configured for the Mac App Store. The app deliberately does not enable App Sandbox: the bundled legacy command-line parser is a child process. Score conversion and display work offline. The optional updater connects to GitHub over HTTPS.

## Conversion: what is actually supported

The converter is [n9yty/nwc2xml](https://github.com/n9yty/nwc2xml/tree/47235bd77a5cd1376426f224a0cda51409b654e0/newversion), the wxWidgets-free C++ port of James Lee's **nwc2xml v1.5**. Its sources are included under `Vendor/nwc2xml`, pinned to commit **47235bd77a5cd1376426f224a0cda51409b654e0**. It parses binary NWC data and inflates `[NWZ]\0` compressed files using zlib, then writes MusicXML 1.1. It supports the legacy NWC versions recognized by upstream, **1.30 through 2.1**. That is a compatibility range, not a guarantee of fidelity for every score or every intermediate version.

**Renaming `.nwc` to `.nwct`, `.nwctxt`, or `.xml` does not convert anything.** This app never does that. It copies the original bytes to an isolated temporary `score.nwc` and invokes the parser with a separate argument array. Text exports renamed to `.nwc` are rejected. Some other converters named `nwc2musicxml` primarily accept NWCTXT; they are not substitutes for this binary parser.

NWC 2.75 binary containers with embedded score text are also supported by the local C++ converter in `Converter/ModernNWC.cpp`. It handles notes, chords, rests, multi-measure rests, standard clefs and keys, time changes, accidentals, ties, slurs, triplets, lyrics and dynamics. Split-duration chords and other unimplemented musical records are rejected rather than silently omitted. Staff layout is regenerated and may differ substantially from the original. Other newer versions and unusual notation may be unsupported. The app rejects failed, malformed, or empty conversions with a readable message. If a newer file fails, use NoteWorthy Composer to export MusicXML, or save a compatible older binary version if your edition supports it; this viewer does not open MusicXML directly. Engraving, layout, lyrics, repeats and other details may differ from the original; check the score before performance or publication. Legacy byte encodings use upstream's UTF-8 / CP1252 fallback. There is no charset setting in this minimal interface.

Input is limited to 16 MB; decompressed binary data and converted XML are limited to 32 MB. Conversion runs off the UI thread with a 20-second timeout. The helper is killed on timeout. Input is copied before conversion; outputs and helper temporary files stay in a private temporary directory and are removed on success/failure. An app crash or forced termination can leave temporary files for macOS to clean up. The original score and neighboring files are never intentionally changed. This is a legacy parser, not a hardened parser for hostile files.

Local modifications to upstream (all included in source):

- Add `<cstddef>` for portable `offsetof` compilation.
- Propagate parser failures through the command-line exit status.
- Zero-initialize the header buffer for short-input checks.
- Limit decompression to 32 MB.

`Vendor/SHA256SUMS` records the vendored source and browser bundle hashes. Source and dependency versions are fixed; build outputs are not claimed to be byte-identical across SDK/compiler versions.

## Runtime dependencies and licenses

Everything below is bundled or part of macOS. End users install **no additional runtime**. Files are processed locally, and the renderer has a content security policy that blocks network connections. System font availability can affect text appearance.

| Component | Version / source | Runtime dependency | License |
| --- | --- | --- | --- |
| NWC Viewer app and project | This repository | SwiftUI, AppKit, Foundation, WebKit (macOS 13+) | GPL-2.0-only; see `LICENSE` |
| nwc2xml | v1.5, pinned port commit above | C++ standard library, system zlib and iconv | GPL v2, `Vendor/nwc2xml/LICENSE.TXT` |
| OpenSheetMusicDisplay | 1.9.2, npm prebuilt UMD bundle | WKWebView JavaScript and SVG | BSD-3-Clause, `Resources/Licenses/OpenSheetMusicDisplay-BSD-3-Clause.txt` |
| OSMD bundled libraries | VexFlow, JSZip, loglevel, typescript-collections and supporting libraries | Included in the UMD bundle | MIT/BSD-compatible notices; JSZip used under its MIT option; see `Resources/Licenses/OSMD-DEPENDENCY-NOTICES.txt` |
| Sparkle | 2.10.1, pinned Swift package | Bundled updater framework and helpers | MIT, `Resources/Licenses/Sparkle-LICENSE.txt` |
| zlib / iconv | macOS system versions | Supplied by macOS; not redistributed here | zlib / Apple's system libiconv distribution terms |

The OSMD bundle was obtained from `https://registry.npmjs.org/opensheetmusicdisplay/-/opensheetmusicdisplay-1.9.2.tgz`. Its upstream npm tarball omits the separate minifier license file named in its header, so this project supplies collected dependency license texts under that filename, plus OSMD's license and author list. `Tools/notice-packages.lock.json` records the packages used to collect those notices; it is **not** a lockfile claiming the precise internal dependency graph used for OSMD's upstream prebuilt bundle.

Preserve all included notices when redistributing. The GPL converter's full corresponding source, its changes, and build instructions are included. When distributing app/helper binaries, supply this corresponding source alongside them under GPL v2; a link to upstream alone is insufficient. Third-party files retain their own notices/licenses. The included test scores come from the converter's GPL repository (`sample/`); `Uncompressed.nwc` is the decompressed `St._Stephen.nwc` fixture. `Modern275.nwc` is a synthetic regression score created for this project, with no user music included. Keep these notices with source distributions.

## Tests

On a Mac, run the hosted XCTest suite (including an actual WKWebView load of the bundled renderer):

```sh
Tools/test-macos.sh
```

Tests cover NWC 2.75 timing changes, multi-measure rests, cautionary accidentals, ties and triplets, compressed and uncompressed binary fixtures, preserving original bytes, filenames with Unicode and shell characters, renamed text rejection, truncated compressed data, unsupported versions, a missing helper, invalid MusicXML, timeout termination, local WebKit rendering and zoom. `Tools/ci/macos.yml` is an optional GitHub Actions workflow template. Copy it to `.github/workflows/macos.yml` using an account with workflow permission to enable CI.

The standalone converter tests also run on Linux with a C++11 compiler, `make`, Python 3, and zlib development headers (iconv is part of glibc). On macOS, zlib/iconv and the compiler come with Xcode:

```sh
make -C Vendor/nwc2xml
python3 Tools/test_converter.py
```

Optional browser regression tests use **test-only** Python dependencies, installed in a virtual environment:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r Tools/requirements-test.txt
python -m playwright install chromium
python Tools/test_renderer.py
# Or use an installed Chromium:
# CHROMIUM_BINARY=/path/to/chromium python Tools/test_renderer.py
```

The browser suite converts all fixtures, renders with network requests monitored, checks SVG A4 proportions, and verifies PDF page counts at 50%, 100% and 200% zoom. It uses a temporary localhost server for testing only; the app uses bundled file URLs. Chromium PDF tests complement the native WebKit test; they do not prove macOS print dialog behavior.

### Validation on Mac (November 15, 2026)

- Built and tested with Xcode 27.2; 10 hosted XCTest cases passed.
- Native WebKit tests verify rendering, zoom, and two nonempty A4 PDF pages at 50%, 100%, and 200% viewing zoom.
- All 5 standalone converter test groups passed, including vendor checksums.
- Browser regression passed for all four fixtures and all three zoom levels, with no external requests or JavaScript errors.
- Visually checked the signed app, its custom icon, file opening, fit width, two-page native print preview, print cancellation, and saved PDF pages.
- Universal Intel/Apple silicon app and helper use Developer ID signing and hardened runtime. The app was notarized and stapled through the existing Xcode account.
- Physical printing was not tested because the printer was offline. Real family scores were not provided; check unusual notation against the original before use.

### macOS release checks

- Open `Tests/Fixtures/Flee.nwc` through Open and Finder; confirm a two-page score, readable lyrics, scrolling, and zoom/reset.
- Open another file; confirm the title and score change. Confirm a failed open clears the old score and displays a useful message.
- Print to preview and export at 50%, 100%, and 200% viewing zoom; confirm two complete A4 pages each time, with no blank trailing page or clipping. Cancel both dialogs and confirm the app remains usable.
- Check filenames containing spaces/Unicode, read-only source folders, repeated open/export cycles, and unsupported newer NWC files.
- Review representative real-world scores against NoteWorthy Composer; fixtures do not cover the full binary format or notation repertoire.

## Source layout

- `App/`: SwiftUI interface, conversion service, WebKit bridge, print/PDF handling.
- `Resources/Web/`: local OSMD bundle, fixed A4 SVG rendering, scrolling/zoom and print CSS.
- `Resources/Licenses/`: notices copied into the app.
- `Vendor/nwc2xml/`: complete converter source, system-only build dependencies.
- `Tests/`: hosted XCTest suite and binary fixtures.
- `Tools/`: deterministic project generator and portable regression tests.

## Signing and sharing with family

See [RELEASE.md](RELEASE.md) for the Developer ID and notarization setup. On a Mac with your own signing identity and Keychain notarization profile, `Tools/release-macos.sh` tests, builds a universal app, signs and notarizes it, and creates a family download containing the app, instructions and corresponding GPL source. If your developer account is already signed in to Xcode, use `Tools/release-xcode.sh`; this uses Xcode’s Keychain authentication without creating a separate notarization profile.

## Measures per line

Choose **Measures per line** in the toolbar or View menu: Automatic, 2, 3, 4, 6 or 8. The default is four, and the app remembers your selection. This changes the score layout and its print/PDF output. Screen zoom only changes on-screen magnification.

Fixed counts override the original line/page breaks. Notation is scaled down to fit dense passages without forcing overlapping notes; higher counts produce smaller notation. The final line may contain fewer measures. Automatic retains the original breaks where present and lets the renderer fit the remaining measures. Very dense scores that cannot fit at the minimum scale fall back to the previous layout with an error message.

## Choose voices

Use the **Voices** toolbar button to select the parts you want. **Only** selects a single part; **All voices** restores the complete score. Click **Apply** to reflow once after making your choices. At least one voice must remain selected. Names come from the score (for example, an alto part may be named “A”). A part containing multiple staves stays together.

Printing and PDF export use exactly the displayed selection and measures-per-line setting. Changing the line density keeps your chosen voices. Opening a different score resets the selection to all its parts. Source files are never modified. Multi-measure rests may be grouped automatically in an extracted part.

The renderer measures note widths once per voice selection, draws only the final fitted layout in normal cases, and reuses the parsed score and layout measurements when changing line density. Print/PDF output is cached until the score, voices or layout changes. Caches stay in memory; nothing is uploaded. `Voices.musicxml` is a synthetic three-part test score authored for this project.

Measure numbers have extra vertical clearance above the staff and nearby notation, including in printed/PDF output. The small local OSMD engraving patch is documented in `Vendor/OSMD-PATCHES.md`.
