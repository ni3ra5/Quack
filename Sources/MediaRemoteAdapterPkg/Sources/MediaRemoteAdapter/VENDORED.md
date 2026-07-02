Vendored verbatim from https://github.com/ejbills/mediaremote-adapter, pinned commit `cf30c4f1af29b5829d859f088f8dbdf12611a046` (BSD-3-Clause, see `LICENSE`). Covers this directory and `Sources/CIMediaRemote/`.

## Local patches (kept minimal; re-apply if re-vendoring)

- `MediaController.libraryPath`: upstream returns `Bundle(for: MediaController.self).executablePath`, which assumes an Xcode-embedded framework whose `Bundle(for:)` resolves to the dylib. Quack builds a hand-assembled `.app` (no Xcode) with the adapter as a loose dylib in `Contents/Frameworks`, where `Bundle(for:)` resolves to `Bundle.main` (the Quack executable — which no longer holds the C symbols once the adapter links dynamically). Patched to point perl at `Bundle.main.privateFrameworksPath + /libMediaRemoteAdapter.dylib`, with the upstream path kept as an SPM/dev fallback. Verified working on macOS 26.5.1 (perl `get` returned live now-playing JSON).
