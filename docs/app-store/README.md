# App Store assets (version 1.0)

- [`store-text.md`](store-text.md): name, subtitle, promotional text, description, keywords, URLs,
  copyright and the App Review notes.
- `screenshots/`: one folder per App Store Connect tab. Upload the files in number order.

| Folder | App Store Connect tab | Size (pixels) |
|---|---|---|
| `iphone-6.3/` | iPhone with Dynamic Island (medium display) | 1206 × 2622 |
| `iphone-duo/` | iPhone Duo | 1398 × 2034 |
| `ipad-13/` | iPad 13" display | 2064 × 2752 |
| `mac/` | Mac | 2880 × 1800 (made by `mac-screenshots.sh`) |

Hum has no Apple Watch app, so the Apple Watch tab stays empty. The header asset on the "Header and
Search Results" tab is optional.

The screenshots use Hum's demo board (`-uiTesting -skipFirstRun -demoFolder -demoHistory`) on iOS 27
simulators, with the status bar set to 9:41 and a full battery
(`xcrun simctl status_bar <device> override ...`). Every picture is an emoji, so no symbol-set credit
is needed. If you add ARASAAC or Mulberry symbols to a screenshot, credit them in the description.

## Mac screenshots

Terminal needs Screen Recording permission. Build the Debug app for "My Mac" in Xcode, then:

```bash
docs/app-store/mac-screenshots.sh /path/to/Debug/Hum.app
```

It writes four shots to `screenshots/mac/`: the child's board, the grown-up editor, dark mode and the
welcome screen.
