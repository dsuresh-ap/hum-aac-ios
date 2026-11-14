# App Store assets (version 1.0)

- [`store-text.md`](store-text.md): name, subtitle, promotional text, description, keywords, URLs,
  copyright and the App Review notes.
- `screenshots/`: one folder per App Store Connect tab. Upload the files in number order. There's no
  welcome screen shot: it says "A voice for your child", and a listing outside the Kids Category can't
  imply that children are the main audience (App Review Guideline 5.1.4(b)).

| Folder | App Store Connect tab | Size (pixels) |
|---|---|---|
| `iphone-6.3/` | iPhone with Dynamic Island (medium display) | 1206 × 2622 |
| `iphone-duo/` | iPhone Duo | 1398 × 2034 |
| `ipad-13/` | iPad 13" display | 2064 × 2752 |
| `mac/` | Mac | 2880 × 1800 (made by `mac-screenshots.sh`) |

Hum has no Apple Watch app, so the Apple Watch tab stays empty.

`header/` has the optional header for the "Header and Search Results" tab, in both supported sizes
(5244 × 2950 and 3840 × 1646). Everything sits in the middle because the App Store crops the header
differently on each device; check it with that tab's Preview button. The same folder has the
optional Search Results asset (3840 × 2560), the same design with bigger tiles because it shows small.
`make-header.swift` draws both: `swift make-header.swift 5244 2950 out.png` for the header, and
`swift make-header.swift 3840 2560 out.png 1.3` for search results.

The screenshots use Hum's demo board (`-uiTesting -skipFirstRun -demoFolder -demoHistory`) on iOS 27
simulators, with the status bar set to 9:41 and a full battery
(`xcrun simctl status_bar <device> override ...`). Every picture is an emoji, so no symbol-set credit
is needed. If you add ARASAAC or Mulberry symbols to a screenshot, credit them in the description.

## Mac screenshots

Terminal needs Screen Recording permission, and the first run asks to let Terminal control System
Events (to bring Hum to the front, so the window looks active). The shots are light, apart from the
dark-mode one, whatever your Mac is set to. Build the Debug app for "My Mac" in Xcode, then:

```bash
docs/app-store/mac-screenshots.sh /path/to/Debug/Hum.app
```

It writes three shots to `screenshots/mac/`: the child's board, the grown-up editor and dark mode.
