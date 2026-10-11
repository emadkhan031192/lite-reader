# Lite Reader

A small, fast, fully offline PDF reader and viewer for Android.

https://github.com/emadkhan031192/lite-reader

Quiet and precise: thin hairlines, small exact type, one indigo accent. No ads,
no account, no network calls — there is no `INTERNET` permission in the manifest
at all.

## Features

- **Files** — library built from SAF folders you add plus files opened from
  outside; search, All/PDF/Office/Starred tabs, recent cards, sort, star,
  multi-select share/remove/merge. Office files open in another app.
- **Reader** — vertical scroll or single-page flow, tap zones, ruler scrubber,
  text search, bookmarks, night mode (soft inversion), pinch zoom to 500%,
  volume-key page turns, keep-awake, per-file last page + zoom restore,
  password-protected PDFs.
- **Contents** — PDF outline with dotted leaders, bookmarks, page thumbnails,
  go-to-page.
- **Annotate & sign** — highlight, underline, strikethrough, pen, text,
  signatures (draw or type); annotations stored in SQLite as normalized
  coordinates and drawn as an overlay; "Save a copy with annotations" exports
  a new PDF (the original is never modified).
- **Tools** — Merge, Split, Reorder, Compress, Scan to PDF, Images to PDF,
  Sign. Every tool runs in a Dart isolate with a progress bar and writes to
  the app's folder, with Open / Share / Save to… afterwards.
- **Settings** — page color, reading options, folder management, offline footer.

Tool outputs are re-rendered as images: text in a copy is not selectable.
The UI says so wherever a tool runs.

## Project layout

```
lib/
  main.dart  app.dart
  core/       # theme, widgets, utils, models, db, platform channels, services, pdf
    pdf/      # pdfrx facade + isolate tool workers
  features/
    library/ reader/ outline/ annotate/ tools/ settings/
  routing/    # go_router
android/      # manifest (VIEW/SEND intent filters), SAF/intent/volume/device plugins
.github/workflows/android.yml
assets/fonts/ # bundled, subsetted (see below)
```

## Fonts

Bundled as assets (no runtime download): **Zen Kaku Gothic New** (400/500/700)
and **DM Mono** (400/500). They are subsetted to Latin + punctuation
(`U+0020-007E`, `U+00A0-00FF`, `U+0100-017F`, punctuation, `€`) to keep the APK
small — about 130 KB total instead of ~7 MB. CJK glyphs are not bundled; PDFs
themselves render with PDFium's own fonts and are unaffected.

## Offline proof

- `android/app/src/main/AndroidManifest.xml` declares no `INTERNET` permission.
- No analytics, no accounts, no network code. SAF + file picker only; camera
  permission is requested at runtime only when opening Scan to PDF.

## Build (GitHub Actions)

`.github/workflows/android.yml` runs on push to `main` and manual dispatch:
Java 17 → Flutter stable → `pub get` → `analyze` → `test` →
`build apk --release --split-per-abi` → uploads `litereader-apks`.

### Release signing (optional)

Add these repository secrets; the build signs with them when present and
falls back to debug signing otherwise (the build never fails):

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | base64 of your `.jks`/`.keystore` file |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias |
| `KEY_PASSWORD` | key password |

```bash
base64 -w0 upload-keystore.jks  # paste into KEYSTORE_BASE64
```

## Swap the app name and icon

- **Name**: `android/app/src/main/AndroidManifest.xml` → `android:label`
  (currently "Lite Reader"); also `pubspec.yaml` description.
- **Icon**: replace the five PNGs in
  `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
  (48/72/96/144/192 px), or use `flutter_launcher_icons`.
- The placeholder icon sources note lives in `assets/icon/README.md`.

## Permissions

| Permission | When |
|---|---|
| `CAMERA` | Declared in manifest; requested at runtime only when opening Scan to PDF, after an in-app explanation. |
| Storage | None at install. SAF document trees + file picker. No `MANAGE_EXTERNAL_STORAGE`. |
| Internet | None. Not declared, not requested. |

## Simplifications and known limits (v1)

- **Lock (password-protect) is hidden**: no permissively-licensed Dart/Flutter
  library can write AES-encrypted PDFs (`pdf` doesn't support encryption;
  implementing ISO 32000 encryption by hand is out of scope). The tile is
  hidden rather than shipping something fake.
- **Tools rasterize**: Merge/Split/Reorder/Compress/Export render pages to
  images and compose a new PDF — text isn't selectable in outputs and vector
  quality tops out at the render DPI. The original file is never touched.
- **Annotate mode is fixed fit-width** (no scroll/pinch inside it); turn pages
  with the edge chevrons. This keeps draw gestures conflict-free.
- **Fonts are Latin-subsetted** (see above).
- **Single-page flow** disables free scroll; pages turn via tap zones, the
  scrubber, or volume keys.
- Export text annotations use a built-in bitmap font (Latin only).
- Thumbnail/search/annotation work needs the PDF readable via a cached copy;
  very large files copy locally on first open.
