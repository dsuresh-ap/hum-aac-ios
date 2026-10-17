# Translating Hum

Hum's source language is US English. Everything a parent or child sees can be translated without touching
code. This page says where each kind of text lives and the rules for translating it.

## Where the text is

| What | File | How it gets there |
|---|---|---|
| Every screen, button, VoiceOver label, error and Shortcuts action | `hum-aac-ios/Localizable.xcstrings` | Xcode adds strings on build. Counts ("3 tiles") use plural variations. |
| App name, camera and microphone prompts, the "Hum File" kind | `hum-aac-ios/InfoPlist.xcstrings` | By hand. |
| Siri and Shortcuts phrases ("Say a phrase with Hum") | `hum-aac-ios/AppShortcuts.xcstrings` | Xcode adds them on build. |
| Emoji search words in the tile picker | `hum-aac-ios/EmojiKeywords.xcstrings` | `swift tools/update-word-catalogs.swift` |
| Praise and compliance phrases Hum warns about | `hum-aac-ios/PraisePhrases.xcstrings` | `swift tools/update-word-catalogs.swift` |
| The starter board | `hum-aac-ios/Resources/starter.<language>.hum.json` | By hand, see below. |

To add a language: in Xcode, select the project → Info → Localizations → **+**, then translate the five
catalogs and (if you can) add a starter board. Test with the scheme's App Language option.

Every string has a comment saying where it appears. Some comments were written by Xcode; if one looks wrong,
fix it in the catalog (or add `comment:` in the code).

## Rules for translators

- **Tiles are the child's voice.** Sample tiles ("Let's go!", "No thank you") are whole phrases a child says.
  Translate them as a child would say them, not word for word.
- **No praise or compliance phrases**, anywhere ("good job", "quiet hands"). See [AGENTS.md](../AGENTS.md).
- **Plain words for parents.** Avoid "setup", "config", "import format" and other computer words. The app
  says "board", "folder", "tile", "grown-up settings" and "Hum file".
- **Apple's names stay Apple's names**: Guided Access, Personal Voice, Private Cloud Compute, Apple
  Intelligence. Use the name Apple uses in your language (Settings shows it).
- **Settings paths** ("Settings → Accessibility → Guided Access") must match what that language's Settings
  app shows.
- **Field names in file problems** ("“spokenText” has the wrong format") stay in English: they are the
  names written in the file.

## Starter board in another language

The starter board is content, not interface text, so it's a file of its own: copy
`examples/starter.hum.json` to `hum-aac-ios/Resources/starter.<language>.hum.json` (for example
`starter.es.hum.json` or `starter.pt-BR.hum.json`) and change only:

- each tile's `spokenText` and `label` (whole phrases, as a child says them),
- the board's `name` ("Home" in that language),
- a tile's `symbol` only if the emoji doesn't fit the translated phrase.

Never change an `id`, `row`, `column`, `function`, `linkedBoardID` or `hidden`, and don't add or remove
tiles. A unit test (`StarterLanguageTests`) checks this. iCloud sync recognises an untouched starter by these
IDs, in every language.

Hum picks the starter in the language its screens are shown in (`pt-BR`, then `pt`), so the starter's words
match the first-run card that quotes three of them ("Let's go!", "All done", "Too loud"): translate that
card with the same words.

## Emoji search words and praise phrases

HumConfig (the shared package) keeps English word lists, because it also runs on Linux and in the
`hum-config` tool, without the app's String Catalogs. The app adds the translated lists at launch
(`ContentLanguage.install()`):

- `EmojiKeywords.xcstrings`: one string per emoji (keys like `emoji_1F9C3`), the words a parent would type to
  find it, separated by commas. They count for search and for the emoji Hum guesses from a tile's words.
- `PraisePhrases.xcstrings`: one string per English phrase; give the usual ways adults say it, separated by
  commas, lowercase, no punctuation. Hum warns about them in the tile editor and leaves them out of AI
  suggestions and Shortcuts.

After changing either English list in HumConfig, run `swift tools/update-word-catalogs.swift`. It keeps
existing translations. A unit test fails when the catalogs are behind.

Other ways we looked at for emoji words: Apple has no public API for emoji names in other languages (the
system's Unicode names are English only), and Unicode's CLDR annotations would be good data but would add a
large third-party file to the app. A translated list of about 170 emoji is small, works offline, and goes
through the same translation tools as everything else.

## Symbol search

The symbol search asks ARASAAC and Global Symbols (Mulberry) in the device's language, and in English when
that finds nothing. ARASAAC supports the languages in `SymbolLibrary.arasaacLanguages`; Global Symbols takes
three-letter codes ("spa"). Only the search word is sent.

## What stays English on purpose

- HumConfig's own messages (`ConfigProblem.text`, `HumConfigError.errorDescription`, the merge summary's
  `sentence`): used by the `hum-config` tool and tests. The app shows its own translated versions
  (`hum-aac-ios/Store/HumConfigText.swift`).
- The AI helper's instructions to the model (`AIHelper.instructions`).
- Symbol licence credits (ARASAAC, Mulberry): kept word for word.
- The word finder's list of little words to skip (`WordFinder.littleWords`). Related matches use Apple's
  on-device word meanings in the boards' own language.
