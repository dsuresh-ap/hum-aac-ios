# Hum privacy policy

Effective: 12 October 2026

Hum is a free, open-source AAC (communication) app. We built it to collect nothing.

## The short version

- **We collect no data.** No analytics, no tracking, no ads, no accounts, no third-party SDKs.
- **We run no servers.** We can't see your boards, photos, recordings or what your child says.
- Hum works fully offline. It uses the network only when a grown-up turns on or starts one of the
  features below.

## What stays on your device

- **Boards, tiles, photos and recordings** are stored in the app on your device.
- **Camera and microphone** are used only when you take a photo for a tile or record a phrase in your
  own voice. The photo or recording stays on the device (or in your own iCloud, if you turn on sync).
- **The "What's this?" camera** (off until you turn it on) lets your child take a picture so Hum can
  guess words for it. The guessing happens on the device, and the picture is thrown away when the camera
  closes: it is never saved, synced or put in history.
- **The history box** (what was said recently) stays on the device. It is never synced or exported.
  You can clear it in Settings.
- **Settings** (voice, display, lock) stay on the device.

## Features that use the network (all off until a grown-up uses them)

| Feature | What is sent | Sent to | Who can see it |
|---|---|---|---|
| **iCloud sync** | Your boards, tiles, photos and recordings | Your own private iCloud database (Apple) | Only you, on your Apple Account. We can't. |
| **AI helper** | The text you type and the words on your tiles. Never photos or recordings. | Your device, or Apple Private Cloud Compute | Apple processes the request and doesn't keep it. We never receive it. |
| **Send to a nearby device** | Your boards, photos and recordings (the same as an exported file), encrypted | Your other iPad, iPhone or Mac nearby, over your local network or Wi-Fi between the two devices. Never the internet. | Only the device you choose: you type the six-digit code it shows on the sending device, then the sending device's code on it to accept. People on the same network can see that Hum is open on its Send or Receive screen, and roughly how big the file is. |
| **Symbol search** | Only the word you search for (and, like any web request, your IP address) | ARASAAC (`api.arasaac.org`, Government of Aragón, Spain) or Global Symbols (`globalsymbols.com`, for Mulberry symbols) | That service. No account, cookie or device ID is sent. The symbol you pick is saved in the tile, so the child's board never uses the network. |

The symbol services have their own privacy policies. Hum sends them nothing that identifies you or
your child.

## Exported files

When you export a `.hum` file, it contains your boards, photos and recordings. You decide where it goes.

## Children

Hum is made for children to use with a grown-up's help. Hum collects no personal information from
anyone, including children under 13. Settings that use the network are behind the grown-up lock.

## Changes

If this policy changes, we will update this page and its date. The full history is in the project's
public repository.

## Contact

Email <apps@dhananjaysuresh.com>, or open an issue at <https://github.com/dsuresh-ap/hum-aac-ios/issues>.
