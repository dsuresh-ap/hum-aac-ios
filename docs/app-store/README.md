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

`header/` has the optional assets for the "Header and Search Results" tab. App Store Connect crops them
differently on each device, so the title and the three tiles stay inside Apple's "art safe area" for each
one, and faded tiles fill the rest (they can be cut off anywhere):

| File | Use | Size | Art safe area |
|---|---|---|---|
| `universal-5244x2950.png` | Header and search results, one image for both | 5244 × 2950 | 1402 × 962 at (1921, 660) |
| `header-3840x1646.png` | Header only | 3840 × 1646 | 1646 × 661 at (1097, 493) |
| `search-results-3840x2560.png` | Search results only | 3840 × 2560 | 2168 × 1030 at (836, 765) |

Upload either the universal image, or the header and search results images. The PNGs have no alpha
channel (App Store Connect refuses transparency). Check the crop with that tab's Preview button.
`header/make-header.sh` draws all three (it needs ffmpeg).

The screenshots use Hum's demo board (`-uiTesting -skipFirstRun -demoFolder -demoHistory`) on iOS 27
simulators, with the status bar set to 9:41 and a full battery
(`xcrun simctl status_bar <device> override ...`). Every picture is an emoji, so no symbol-set credit
is needed. If you add ARASAAC or Mulberry symbols to a screenshot, credit them in the description.

## App previews

Two app previews for each tab, in the same order on every device. All are 30 fps H.264 (11 Mbps) with a
silent stereo AAC track (previews start muted), 15 to 30 seconds long, and show only the app (App Review
Guideline 2.3.4).

1. `1-history-fills-up.mp4`: tiles are tapped and the history box fills up, through the Food folder and
   back Home.
2. `2-add-a-tile.mp4`: hold the lock, add "To the playground!", save, and tap the new tile on the board.

| Folder | Size | Recorded on |
|---|---|---|
| `previews/iphone-6.3/` | 886 × 1920 | iPhone 17 Pro simulator (iOS 26.5; same 1206 × 2622 screen) |
| `previews/iphone-duo/` | 886 × 1920 | iPhone Duo simulator (iOS 27.1), outer screen, fitted on Hum's background |
| `previews/ipad-13/` | 1200 × 1600 | iPad Pro 13-inch (M5) simulator (iOS 26.5) |
| `previews/mac/` | 1920 × 1080 | the Mac app's window on Hum's light teal |

iPhone Duo previews use the standard iPhone size, not the Duo's own screen shape, so the whole screen is
fitted inside 886 × 1920 with Hum's background color above and below.

To make one: record with `xcrun simctl io <device> recordVideo --codec=h264 <raw.mov>` (on the iPhone
Duo add `--display=1` and use `--codec=hevc`: its H.264 recording keeps only the first frame), or record
the Mac window with `screencapture -v -R<x,y,w,h>`. Then convert:

```bash
docs/app-store/previews/make-preview.sh <raw.mov> <out.mp4> <WxH> <fill|fit|window> [start] [hold] [length]
```

`fill` crops to the size (iPhone, iPad), `fit` fits the whole screen inside it (iPhone Duo) and `window`
puts a Mac window on the teal background. `start` and `length` trim the recording; `hold` keeps the last
frame a little longer to reach 15 seconds.

## Mac screenshots

Terminal needs Screen Recording permission, and the first run asks to let Terminal control System
Events (to bring Hum to the front, so the window looks active). The shots are light, apart from the
dark-mode one, whatever your Mac is set to. Build the Debug app for "My Mac" in Xcode, then:

```bash
docs/app-store/mac-screenshots.sh /path/to/Debug/Hum.app
```

It writes three shots to `screenshots/mac/`: the child's board, the grown-up editor and dark mode.
