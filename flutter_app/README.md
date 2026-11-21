# السوق العربي — Flutter Native (مرحلة الاختبار)

This is the native Flutter marketplace test app. The original HTML website and backup files are intentionally untouched.

## Current native modules
- Arabic RTL shell with five bottom sections: Home, Search, Favorites, Messages, Account.
- The original 11 marketplace categories.
- Live listings read from the existing Supabase `market_listings` table.
- Email sign-in / sign-up through the existing Supabase Auth project.
- New listing flow with camera and gallery selection, up to 8 images, large preview and reorderable thumbnails.
- The first photo in the order is uploaded first and stored as `photo_urls[0]`, the cover image.
- Binary upload uses Supabase Storage `uploadBinary` to the existing `market-photos` bucket. No Base64 conversion.
- Listing rows use the existing table columns only.
- OpenStreetMap map picker with device location and reverse geocoding to fill city/district.
- Private conversations and messages use the existing `market_conversations` and `market_messages` tables.
- Favorites are stored locally on the device because the current database has no favorites table.
- Account listing management supports closing and deleting the signed-in user's own listings.

## Existing backend
Project: `xhyobwcaljmoakyvjajb`
Storage bucket: `market-photos`
Tables used: `market_listings`, `market_conversations`, `market_messages`
No database tables, rows, or policies are changed by this Flutter app.

## Build
GitHub Actions builds a debug APK. It requires the repository Actions secret `SUPABASE_ANON_KEY`, containing only the existing Supabase anon/publishable key. Never use a service-role or secret key in the APK.

## Preserved photo test
The earlier verified photo-only app is preserved at `lib/photo_test_main.dart` as a source reference. The app entry point is now `lib/main.dart`.

## Not yet production-certified
This is an initial native migration for staged testing, not a claim that every feature of the existing website has been ported or validated. Push notifications, voice messages, full category-specific fields, advanced listing filters, iOS build/signing, and end-to-end tests across old/new devices remain future validation work.
