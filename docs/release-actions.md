# Release actions: legal, credits and disclaimers

Work found in the pre-release legal and IP review (2026-10-12). Part 1 is for a coding agent with
**Xcode access** (the Xcode MCP). Part 2 is for the owner: App Store Connect and other non-code tasks.

Already done in the same change (no Xcode needed): the TD Snap importer was removed from the repo,
[`privacy.md`](privacy.md), [`support.md`](support.md) and [`NOTICE`](../NOTICE) were added, the README got
a disclaimer and licence note, `ITSAppUsesNonExemptEncryption = NO` went into `Hum-Info.plist`, and
`CONTRIBUTING.md`, `Hum-agent-prompt.md` and `docs/PLAN.md` §9 were brought up to date.

---

## Part 1: tasks for a coding agent with Xcode

Common preamble (paste it first):

> You are working in https://github.com/dsuresh-ap/hum-aac-ios, a free, open-source AAC app for
> Gestalt Language Processors. Read `CLAUDE.md`, `AGENTS.md`, `docs/PLAN.md` and this file first.
> Build and test with the Xcode MCP as `CLAUDE.md` describes: build for testing, run tests on an
> **iOS 27 simulator** (never on "My Mac"), then switch the destination back to "My Mac". Also run
> `swift test --package-path Packages/HumConfig`. Hard rules: no dependencies, no new network use, every
> new source file starts with the Apache-2.0 SPDX header, plain short comments. **Nothing in this file
> may appear in child mode**: no banners, tooltips or disclaimers on the child's board. Parent-facing text
> is plain and warm (see `CONTRIBUTING.md`). Do the tasks in order; each one is its own commit.

### Task 1: "About Hum" screen in Settings

Replace the "Credits" section at the end of `hum-aac-ios/ParentMode/SettingsView.swift` (search for
`Text("Credits")`) with a `NavigationLink("About Hum")` to a new `ParentMode/AboutView.swift`. It shows:

1. App name, version and build (`CFBundleShortVersionString` / `CFBundleVersion`).
2. **Important** (two sentences, the same as `README.md` → "Important"):
   - "Hum is a communication tool. It is not a medical device or therapy, and it doesn't replace a
     speech-language pathologist."
   - "Don't rely on Hum as the only way to call for help in an emergency."
3. Links (open in the browser with `openURL`, like `SetupSharingView.swift` already does):
   - Privacy policy → `https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/privacy.md`
   - Help and support → `https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/support.md`
   - Source code → `https://github.com/dsuresh-ap/hum-aac-ios`
   - Licence (Apache-2.0) → `https://github.com/dsuresh-ap/hum-aac-ios/blob/main/LICENSE`
   Put the URLs in one place (e.g. a small `enum HumLinks`), so the owner can change them to a website later.
4. "Symbols": the existing `SymbolLibrary.credits` text.
5. "Licence": "Hum is free and open source under the Apache License 2.0. It comes with no warranty."
6. The trademark line from `NOTICE` ("Apple, iCloud, … Hum is not affiliated with …").

Done when: the screen works on iPhone, iPad and Mac, passes VoiceOver (every link has a clear label)
and Dynamic Type at the largest size, and a UI test opens it from Settings.

### Task 2: first-run note and how to get back in

In `hum-aac-ios/Onboarding/FirstRunView.swift`, on the last step (`"How do you want to start?"`), add a
short footnote, not a new page:

- "To change things later, press and hold the lock for 3 seconds."
- "Hum is a communication tool, not therapy or a medical device." with a "Privacy" link (same URL as
  Task 1).

Done when: the footnote is readable at the largest Dynamic Type size without hiding the start buttons.

### Task 3: AI helper note

In `hum-aac-ios/AI/AIHelperView.swift`, under the "Privacy" section, add one line:
"Suggestions come from AI and can be wrong. Nothing is added until you choose it." Keep the existing
text. Done when: the line shows for both on-device and Private Cloud Compute.

### Task 4: keep the symbol credit with the tile, and put it in exported files

Why: ARASAAC (CC BY-NC-SA) and Mulberry (CC BY-SA) require credit and licence to travel with the
pictures. Today, a chosen symbol becomes a plain JPEG, and an exported `.hum` has no credit.

1. **HumConfig** (`Packages/HumConfig`):
   - Add `public var imageCredit: String?` to `HumTile` in `Sources/HumConfig/HumDocument.swift`
     (add it to `knownKeys`, `init(from:)`, `encode(to:)`, the memberwise init with a `nil` default).
   - Add it to `schema/hum.schema.json` **and** `Sources/HumConfig/Resources/hum.schema.json`:
     optional string, max 500 characters, description "Credit and licence of the picture, for example
     a symbol set's attribution. Kept when the picture is exported."
   - Validator: warn (not error) if `imageCredit` is set but `image` is not.
   - In `HumPackage.write` (`Sources/HumConfig/HumPackage.swift`): if any exported tile has an
     `imageCredit`, add a `CREDITS.txt` entry at the root with one line per unique credit, plus
     "Some pictures in this file come from the symbol sets above and keep their licences." Make sure
     `HumPackage.read` ignores `CREDITS.txt` (it must not become media) and `hum-config unpack` writes it.
   - Document the field in `docs/CONFIG.md`. Tests: round trip of `imageCredit`, `CREDITS.txt`
     present only when needed, and a package with `CREDITS.txt` still imports.
2. **App**:
   - Add `var imageCredit: String?` to `Tile` in `hum-aac-ios/Model/Models.swift`, next to `imageData`.
     It must be optional (SwiftData lightweight migration and CloudKit both need that).
   - `EmojiPicker.swift`: change the symbol `onPick` callback to pass the credit too
     (`source.credit`), and store it in the tile in `TileEditorSheet.swift`.
   - Set `imageCredit = nil` whenever the picture is replaced by a photo or removed.
   - Map it both ways in `hum-aac-ios/Store/ConfigBridge.swift` (export and import).
   - In the tile editor, show the credit in small secondary text under the picture.
   - Tests: picking a symbol keeps the credit; replacing it with a photo clears it; export → import
     keeps it.
   - Note for the owner in the PR: the new CloudKit field must be deployed to the **production**
     CloudKit schema (CloudKit Console) before release.

### Task 5: labels and tooltips for icon-only buttons (parent mode only)

Audit `hum-aac-ios/ParentMode/` for buttons that show only an icon, or whose meaning is not clear. Give
each one an `accessibilityLabel` and, on macOS, a `.help(...)` tooltip. Some already have one
(`ParentEditorView.swift`: "Add a tile…", "Suggest tiles…", "Open the folder…"). Do not add tooltips
or hints to child mode (`ChildMode/`). Done when: VoiceOver reads a clear name for every control in
parent mode and every icon-only button on the Mac shows a tooltip.

### Task 6: accessibility check for the App Store labels

App Store Connect asks which accessibility features the app supports. Test each one on iPhone and iPad
(iOS 27 simulator plus Accessibility Inspector) for the child board, the tile editor, Settings and the
first run: **VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone,
Sufficient Contrast, Reduced Motion**. Fix small problems. Write the results in a new
`docs/accessibility.md` as a table (feature, pass/fail, notes), so the owner declares only what passes.

### Task 7: release build check

Archive the app (Release configuration) and confirm:
- `ITSAppUsesNonExemptEncryption` is `NO` in the built Info.plist.
- `aps-environment` is `production` in the signed entitlements of the archive.
- `PrivacyInfo.xcprivacy` is in the bundle; Xcode's privacy report shows no undeclared
  required-reason API.
- No `Snap`, `.sps` or Tobii text is anywhere in the app bundle (`strings` on the binary).
Report the results in the PR; change nothing else.

---

## Part 2: owner tasks (not code)

- [x] **Contact email** in [`privacy.md`](privacy.md): apps@dhananjaysuresh.com. Make sure it forwards to an inbox you read.
- [ ] **Name check:** search "HUM" in class 9 (software) on USPTO (and EUIPO for the EU). Search the
      App Store. Consider "Hum AAC" as the App Store name.
- [ ] **Privacy policy URL** and **Support URL** in App Store Connect: the GitHub links in Task 1, or a
      GitHub Pages site made from `docs/`.
- [ ] **Privacy label:** "Data Not Collected". Read the symbol-search row in `privacy.md` again before
      you submit, and keep the label and the policy the same.
- [ ] **Category:** Education. Do **not** choose the Kids Category (it needs stricter parental gates on
      every link and limits network use).
- [ ] **Age rating** questionnaire: answer it honestly; expect 4+.
- [ ] **EU Digital Services Act:** declare trader status. A free, non-commercial hobby app can usually
      say "not a trader" (then your address and phone are not shown).
- [ ] **Seller name:** an individual account shows your legal name on the store. Use an organisation
      account if you don't want that.
- [ ] **Accessibility Nutrition Labels:** declare only what `docs/accessibility.md` (Task 6) says passes.
- [ ] **App Store text and screenshots:** no medical or therapy claims ("treats", "improves speech",
      "therapy for autism"). Say "communication tool". No movie characters or ARASAAC symbols in
      screenshots without their credit.
- [ ] **TD Snap importer:** it is now only in git history (commit `91dae8e`) and in a patch file. If the
      repo is public, the code is still visible in history. Keep it in a **private** repo for your own use.
      Read the Snap licence (EULA) you agreed to for any reverse-engineering clause, and never share files
      converted from Snap.
- [ ] Optional: ask a lawyer (many legal-aid clinics help open-source and non-profit projects free) to
      read `privacy.md` and the App Store text once.
