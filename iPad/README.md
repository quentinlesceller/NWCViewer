# NWC Viewer for iPhone and iPad

Open NWCViewer.xcodeproj, choose NWCViewerPad and select an iPhone or iPad simulator, or a provisioned device running iOS or iPadOS 16 or later. Run the app, tap the folder and choose a binary NWC score in Files. The toolbar offers all voices or one part, measures per line, and the system print sheet. Pinch and scroll to read. Conversion and engraving run locally. Mac and iPad use the same score reader in Converter/.

For development smoke tests, a Debug build also accepts -FixtureName followed by the name of a score already in its simulator Documents directory. Production builds omit this entry point. The Mac updater is only linked by the Mac target.
