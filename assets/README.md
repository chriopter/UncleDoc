# Assets

This folder is the source of truth for app branding assets.

## App Icons

- Web source files live in `assets/icons/web/`
- iOS source files live in `assets/icons/ios/`
- macOS source files live in `assets/icons/macos/`

When the app icon or logo changes, update these generated source files first.

## Where Icons Are Used

- Rails favicon and PWA files are served from `public/`
- Rails HTML references are in `app/views/layouts/application.html.erb`
- Rails PWA manifest is in `app/views/pwa/manifest.json.erb`
- iOS app icons are in `ios/UncleDoc/Assets.xcassets/AppIcon.appiconset/`

## Replace Checklist

If branding changes, replace icons in all of these places:

1. Update the source icon set in `assets/icons/web/` and `assets/icons/ios/`
2. Copy web icons into `public/`
3. Copy iOS icons into `ios/UncleDoc/Assets.xcassets/AppIcon.appiconset/`
4. Keep the filenames referenced by the Rails layout and PWA manifest in sync

## Current Web Files

- `public/favicon.ico`
- `public/apple-touch-icon.png`
- `public/icon-192.png`
- `public/icon-192-maskable.png`
- `public/icon-512.png`
- `public/icon-512-maskable.png`
- `public/icon.png`

`public/icon.svg` is currently unused.
