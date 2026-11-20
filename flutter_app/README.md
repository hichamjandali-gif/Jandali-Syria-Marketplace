# Jandali Flutter photo test

This is an isolated native Flutter test app. It does **not** replace the live marketplace yet.

## What this test covers
- Native Android/iOS image picker for gallery and camera.
- Up to 8 selected photos, large preview, thumbnails, remove and reorder.
- Optional upload of selected image bytes to the existing Supabase Storage bucket `market-photos`.
- Uploads go under `flutter-photo-test/`; no database tables or policies are changed.

## Build locally

From this folder:

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

To enable the optional Storage upload, provide the existing Supabase project URL and its **anon/publishable key** at build time:

```bash
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://xhyobwcaljmoakyvjajb.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_EXISTING_ANON_OR_PUBLISHABLE_KEY
```

Never use a Supabase service-role key in a mobile app or commit secrets to this repository. Without these values, gallery and camera preview can still be tested; upload is disabled.

## Important scope
This is a photo-picker/storage test screen only. It does not yet implement marketplace login, listings, search, chat, or database inserts. The existing HTML marketplace and its backup files are left unchanged.
