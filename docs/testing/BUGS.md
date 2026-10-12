# Hum bug log (end-to-end test pass, 2026-10-11)

Found while walking every screen on the iOS 27 simulator (iPhone 18 Pro, iPhone 18 Pro Max, iPad Pro 13-inch) with the UI
tests in `HumUITests/` and by hand. A bug that a UI test reproduces is wrapped in
`XCTExpectFailure("HUM-0xx …")` in that test: the suite stays green, and the test starts failing
(“expected failure but none recorded”) once the bug is fixed. That's the cue to remove the wrapper.

**Severity:** Critical (data loss, or the child loses access to words) · High (a main flow is broken
or misleading) · Medium (works, but confusing or against the spec) · Low (polish).
**Kind:** Bug · UI (layout/sizing) · Text (wording) · Jargon (words a parent shouldn't see) · A11y.
**Found by:** the UI test that shows it, “code” (read in the source, not run), or “by hand”.

**2026-10-12:** every bug below except HUM-014 is fixed on branch `e2e-tests-and-bug-log`. The
`XCTExpectFailure` wrappers are gone: the same UI tests now check the fixed behavior, and
`HumTests/BugFixTests.swift` covers the store-level fixes. How each one was fixed is in
[Fixes](#fixes-2026-10-12) at the end. Ones marked “confirm on device” are in section 12 of the human test plan.

| ID | Sev | Kind | Screen | Summary | Status |
|----|-----|------|--------|---------|--------|
| [HUM-001](#hum-001) | Critical | Bug | Import | Merging a whole setup strands its Home: all imported boards (and its protest tiles) become unreachable | Fixed |
| [HUM-002](#hum-002) | Critical | Bug | Editor | Undo after deleting a tile doesn't bring it back; the tile is lost | Fixed |
| [HUM-037](#hum-037) | High | Bug | Import (iOS) | Imported SVG symbols stay blank for minutes after import (1 of ~40 appeared in 90 s) | Fixed |
| [HUM-038](#hum-038) | High | Bug | Import | Undo after “Replace everything” doesn't bring the old boards back | Fixed |
| [HUM-047](#hum-047) | High | Bug | AI helper | AI tiles with their own folder go to a new folder nothing opens, so they seem to vanish | Fixed |
| [HUM-048](#hum-048) | High | Bug | Child (sound) | Static or hiss at the end of spoken phrases | Fixed |
| [HUM-004](#hum-004) | High | Bug | First run | “Import a setup” makes an empty Home first; cancelling leaves a blank board, importing hits HUM-001 | Fixed |
| [HUM-015](#hum-015) | High | Bug | Tile editor | Cancelling the camera deletes the tile's existing photo | Fixed (confirm on device) |
| [HUM-003](#hum-003) | Medium | Bug | First run | The grid size picked in setup is ignored for the starter board | Fixed |
| [HUM-006](#hum-006) | Medium | UI | Editor (iPhone) | Tapping a folder tile opens the folder instead of editing it | Fixed |
| [HUM-008](#hum-008) | Medium | Bug | Editor | “Delete tile” in the long-press menu deletes without asking | Fixed |
| [HUM-009](#hum-009) | Medium | UI | Welcome (iPhone) | Sample tiles are wider than the screen; the subtitle is cut off on both sides | Fixed |
| [HUM-017](#hum-017) | Medium | Bug | First run, Settings | Robotic legacy voices (Fred, Junior, Kathy, Ralph…) are offered as top picks | Fixed |
| [HUM-027](#hum-027) | Medium | UX | Import, Editor | After a big import nothing says where the boards went; the board menu is a flat list of 116 | Fixed |
| [HUM-022](#hum-022) | Medium | Jargon | Settings | “For developers” section and latency screen are visible to every parent | Fixed |
| [HUM-023](#hum-023) | Medium | Jargon | Setup & sharing | iCloud rows show CloudKit console steps and raw error text | Fixed |
| [HUM-031](#hum-031) | Medium | Bug | AI helper | Settings says the AI isn't ready, but the helper shows the “Suggest tiles” form anyway | Fixed (confirm on device) |
| [HUM-036](#hum-036) | Medium | UX | Editor (iPhone) | “Done” is a bare checkmark; History, Setup & sharing and Settings hide in “⋯” | Fixed |
| [HUM-040](#hum-040) | Medium | Bug | Home & folders | “Make Home board” on a board without protest tiles gives no warning | Fixed |
| [HUM-041](#hum-041) | Medium | Bug | Editor | The one-time Guided Access tip sometimes never appears | Fixed |
| [HUM-043](#hum-043) | Medium | UI | Child, Editor | Labels break in the middle of words on narrow tiles (“Clothin/g”, “Weathe/r”) | Fixed |
| [HUM-044](#hum-044) | Medium | Bug | Child (iPad) | The 3-second lock needs a much longer hold on iPad (3.5 s fails, 6 s works) | Fixed (confirm on device) |
| [HUM-005](#hum-005) | Low | Jargon/UI | Editor | “Tiles are smaller than 88 points…” is developer wording, and cut off | Fixed |
| [HUM-007](#hum-007) | Low | UI | Editor (iPhone) | Pencil and camera badges cover the tile's picture | Fixed |
| [HUM-010](#hum-010) | Low | UI | Editor (iPhone) | Inside a folder, the help text is squeezed into a 9-line column; it takes a quarter of the screen | Fixed |
| [HUM-011](#hum-011) | Low | Text | Import preview | `Chat: “”` for folders, `I need a break.: “I need a break.”`, list silently stops at 30 | Fixed |
| [HUM-012](#hum-012) | Low | Text | Settings | Footer points to “Say it in your own voice”; the button is called “Record your voice” | Fixed |
| [HUM-013](#hum-013) | Low | Bug | Settings, Home & folders | New-board size can be set to 1 × 1, which the grid sheet says is too small | Fixed |
| [HUM-016](#hum-016) | Low | UI | First run (voice) | The natural-voice help card is cut off with “…” | Fixed |
| [HUM-018](#hum-018) | Low | Text | Tile editor, Paste phrases | Suggested label stops after four words: “Let's go to the” | Fixed |
| [HUM-019](#hum-019) | Low | Text | Tile editor, Paste phrases | First emoji idea for “Let's go to the park/playground” is a door 🚪 | Fixed |
| [HUM-020](#hum-020) | Low | UI | AI helper | Intro bullet points are cut off (“…are us…”, “…until yo…”) | Fixed |
| [HUM-021](#hum-021) | Low | A11y | Child (history box) | VoiceOver reads “Said: Hi!. Say it again.” | Fixed |
| [HUM-024](#hum-024) | Low | Text | Editor tray | Tiles moved off a shrunk board are called “new tiles” | Fixed |
| [HUM-025](#hum-025) | Low | Text | Settings | “Start the new tap right away”, “Speak when the finger” are hard to read | Fixed |
| [HUM-026](#hum-026) | Low | UX | History | “Clear” sits right next to “Done” | Fixed |
| [HUM-028](#hum-028) | Low | UX | Tile editor | Picking an emoji while a photo is set does nothing visible | Fixed |
| [HUM-029](#hum-029) | Low | UX | Grid size | The board's current size (5 × 4 starter) isn't a quick size, so nothing is selected | Fixed |
| [HUM-032](#hum-032) | Low | Jargon | Grid size, Editor | “phone layout”, “wider than 4 or taller than 8”, “Phone page 1 of 2” | Fixed |
| [HUM-034](#hum-034) | Low | Text | Home & folders | Section header “Home and folders” repeats the title | Fixed |
| [HUM-035](#hum-035) | Low | A11y | Child | A tile with no words is read as “<label>, folder” even when it isn't a folder | Fixed |
| [HUM-039](#hum-039) | Low | Bug | Home & folders | Renaming a folder doesn't rename the tile that opens it | Fixed |
| [HUM-042](#hum-042) | Low | UX | Setup & sharing | Export can take over 10 s with no “preparing…” feedback | Fixed |
| [HUM-045](#hum-045) | Low | UI | All sheets (iPad) | Sheets are small form sheets on a 13" iPad; Settings needs lots of scrolling | Fixed (confirm on device) |
| [HUM-046](#hum-046) | Low | UI | First run (iPad) | Welcome and grid steps use a small block in the middle of a big screen | Fixed |
| [HUM-014](#hum-014) | ? | Bug? | Editor | First tap on “⋯” (and after a sheet closes) sometimes ignored; simulator panel only so far | Open (device) |

---

## Critical

### HUM-001
**Merging a whole setup strands its Home.** Critical · Bug · Import · *Found by:* by hand,
`ImportUITests.testMergedSetupIsReachableFromHome`

Steps: start with the starter board → Setup & sharing → Import `Express2-v2.hum` (115 boards, 6 × 8 Home)
→ keep **Merge** (the default) → Merge.

Expected: the child can reach the imported boards, e.g. a folder tile on Home that opens the imported Home,
or a clear choice in the preview (“Use this file's Home as Home?”).
Actual: `MergePlanner.planMerge` sets the incoming Home's `isHome = false` and never links to it. The board
list now has two boards called “Home” (one a folder). No tile opens the second one, so **all 115 imported
boards are unreachable for the child**, including its protest/regulation tiles (“I don't like it”, “it's too
loud”, “I need a break.”), which breaks the rule that protest tiles stay reachable from Home. The preview
said “115 new boards… No tiles will move.” and gave no hint of this.

Fix ideas: when the incoming file has its own Home, (a) add a folder tile to the existing Home in its first
free spot that opens it, named after the file, or (b) ask in the preview. Also give the demoted board a
distinct name (“Home (Express2)”).

### HUM-002
**Undo after deleting a tile loses the tile.** Critical · Bug · Editor · *Found by:*
`EditorUITests.testDeleteFromEditorConfirmsAndUndoes`, `EditorUITests.testUndoAfterMenuDelete`

Steps: edit mode → long-press “up” → Delete tile (or tile editor → More options → Delete tile → confirm)
→ tap Undo.

Expected: “up” comes back in its spot (the delete dialog even promises “You can undo this.”).
Actual: Undo greys out (the step is used up) but “up” doesn't come back, not in the editor and not on the
child's board after Done. The tile is gone for good. Undo of *adding* a tile works
(`HumUITests.testEditGateAddTileAndUndo`). Suspect: SwiftData undo of a delete doesn't restore the
`board` relationship, so the restored tile is orphaned; add a unit test in `MotorPlanTests` that deletes
then undoes, and checks `board.placedTiles`.

## High

### HUM-047
**AI suggestions in their own folder go to a folder nothing opens.** High · Bug · AI helper · *Found by:*
the owner while testing on a device; confirmed in code and by
`ProposalCheckerTests.suggestedTilesInANewFolderAreReachable` (known issue)

The model may give a tile a `boardName` (its instructions say to when “a new sub-board clearly helps”,
e.g. “Trains”). `ProposalChecker.document(from:targetBoardID:existing:)` then makes a new board with that
name, but no folder tile on the board being edited (or on Home) opens it. After **Add**, the tiles aren't
on the board the parent was looking at, and the child can't reach them. They're only findable in
Home & folders (“No tile opens this folder yet”) or the board menu. The checklist's small “Goes to Trains”
caption is the only hint. Two related routes:
- If `boardName` matches an existing board's name (e.g. “Home” while editing Food), tiles go to that board
  instead of the active one.
- Protest/regulation suggestions are also copied to Home on purpose (rule 6, with a note).

Tiles *without* a `boardName` correctly go to the board being edited
(`ProposalCheckerTests.suggestionsGoToTheBoardBeingEdited`). Fix: when a suggestion makes a new folder, add
a folder tile for it to the board being edited (first empty spot, or the tray), and after Add show a
banner (“Added 4 tiles to Trains, a new folder on Food. Open it”). Consider defaulting to the active board
unless the parent ticks “Put these in a new folder”.

### HUM-048
**Static or hiss at the end of phrases.** High · Bug · Child mode (sound) · *Found by:* the owner by ear;
confirmed by rendering phrases on the simulator and measuring them

`AVSpeechSynthesizer.write` delivers speech in 256-frame chunks at 22.05 kHz (~11.6 ms each).
`SpeechRenderer` resampled every chunk to 48 kHz with a new `AVAudioConverter`, so each chunk edge had a
small glitch: noise spikes exactly every 557 samples (256 × 48000 / 22050), and about twice the
high-frequency energy of a clean resample. It's heard as static or hiss, most of all in the quiet end of a
phrase. The kept 40 ms tail also ended with a hard cut. Clips are cached on disk, so the hiss stayed until
the cache was cleared.

**First run “Import a setup” creates an empty Home first.** High · Bug · First run · *Found by:* code
(`FirstRunView.startChoice`)

The button calls `model.finishFirstRun(.empty(rows:columns:))` and only *then* opens the file picker.
- Cancel the picker: the parent is left on a blank board, setup is marked complete, and there is no way back
  to the setup screens.
- Pick a file: it merges into the new empty “Home”, so the file's own Home is demoted (HUM-001) and the
  child sees an empty board.

Fix: only finish setup after a successful import, and when the existing setup is just an empty Home,
let the file's Home become Home (or use Replace).

### HUM-015
**Cancelling the camera deletes the existing photo.** High · Bug · Tile editor · *Found by:* code
(`TileEditorSheet`: `CameraPicker { data in imageData = data.flatMap(...) }`; cancel calls `onFinish(nil)`)

Steps (iPhone/iPad with a camera): edit a tile that has a photo → Take photo → Cancel.
Expected: the old photo stays. Actual: `imageData` becomes nil; Save then removes the photo.
Needs a real device to confirm (no camera in the simulator); listed in the human test plan.

### HUM-037
**Imported SVG symbols stay blank on iOS.** High · Bug · Import · *Found by:*
`ImportUITests.testReplaceEverythingThenUndo` (screenshots right after import and 90 s later)

`Express2-v2.hum` has a picture for every Home tile (`media/sym5424.svg`… converted from TD Snap). On iOS,
SVGs are turned into JPEGs in the background *after* the import (`ImportService.renderImportedSVGs`, one
off-screen `WKWebView` per picture). Right after the import nearly every folder tile on Home and every tile
in “Chat” shows only its color and label; 90 seconds later just one more picture had appeared. The parent
isn't told pictures are still coming, and the child gets a board of blank tiles. The import's own
progress bar (“Preparing pictures… 1581 of 1581”) already finished, so it looks done. Check how long the
full conversion takes and whether some SVGs fail for good (e.g. ones with a negative `viewBox` origin,
like `sym2046.svg`'s `viewBox="938 -1826 568 484"`). Convert inside the import's progress, or show
progress for the background pass.

### HUM-038
**Undo after “Replace everything” does nothing.** High · Bug · Import · *Found by:*
`ImportUITests.testReplaceEverythingThenUndo`

Replace everything → confirm (the dialog says “A backup of your current boards is saved first, and you can
undo.”) → Done → Home → back into edit mode → Undo. Still the imported 6 × 8 Home, and Undo stays enabled.
The starter board doesn't come back. Possibly the background picture conversion (HUM-037) is saving changes
that end up on top of the undo stack, or the replace isn't one undo group. Related to HUM-002.

## Medium

### HUM-040
**A board without protest tiles can become Home with no warning.** Medium · Bug · Home & folders ·
*Found by:* `BoardsUITests.testMakeAFolderHome`

Long-press a folder (e.g. Food) → Make Home board. The child's Home is now Food, which has no “stop”, “no
thank you” or “help”. The spec says protest and regulation tiles stay on Home. Warn, offer to copy the
protest tiles over, or keep a protest row on every Home.

### HUM-041
**The one-time Guided Access tip sometimes never appears.** Medium · Bug · Editor · *Found by:*
`ParentToolsUITests.testGuidedAccessTipShowsOnce` (failed 1 of 2 runs)

After first-run setup, holding the lock opened the editor with no tip. On the next run it showed. The
alert is triggered from `onAppear` while the screen switches from the child grid to the editor, which
SwiftUI can drop. Since it's shown only once, a missed tip is never shown again.

### HUM-043
**Labels break in the middle of words.** Medium · UI · Child and editor · *Found by:* screen tour after import

On narrow tiles (8 columns: small iPads, a small Mac window, or the iPhone if the phone layout is off),
long single words wrap mid-word: “Clothin/g”, “Weathe/r”, “Entertai/nment”, “Questio/ns”, “Feeling/s”,
“Technol/ogy”. `minimumScaleFactor(0.6)` isn't enough. Prefer shrinking the font further for single long
words over breaking them (`.allowsTightening`, a lower scale factor, or one line for one-word labels).

### HUM-044
**The lock needs a much longer hold on iPad.** Medium · Bug · Child mode · *Found by:* a probe test on
iPad Pro 13-inch (iOS 27): `press(forDuration: 3.5)` on the lock never opened grown-up mode; a 6 s press did.
On iPhone 3.5 s works.

The lock sits ~40 pt from the top edge, where iPadOS holds back touches for its own edge gestures, so the
`DragGesture` (and the 3 s timer) start late. Parents told “press and hold for 3 seconds” will let go too
early and think it's broken. Move the lock down a little or start the timer from a gesture that isn't
delayed. Check on a real iPad (human test plan).

### HUM-003
**Grid size picked in setup is ignored for the starter board.** Medium · Bug · First run · *Found by:*
`FirstRunUITests.testStarterBoardHonorsASmallGridChoice`

The step says “Fewer, bigger tiles are easier to start with” and offers 2 × 2, 3 × 3, 3 × 4. With the
starter board, any choice smaller than 5 × 4 is silently dropped (`growHomeToChosenSize` only grows). A
parent who picked 2 × 2 gets 18 small tiles. Either put the starter's extra tiles in folders / pages for
small grids, or say on the start screen that the starter board is 5 × 4.

### HUM-006
**iPhone editor: tapping a folder tile opens the folder, not its editor.** Medium · UI · *Found by:* by hand
and `EditorUITests.testTappingAFolderTileEditsIt` (iPhone 18 Pro; doesn't happen on 18 Pro Max)

On narrow tiles the “Open” chip (icon-only) sits over the middle of the tile, on top of the picture. The
natural tap target, the picture, opens the folder. The only way to rename a folder is the long-press menu.

### HUM-008
**Long-press “Delete tile” doesn't confirm.** Medium · Bug · Editor · *Found by:*
`EditorUITests.testDeleteFromMenuAsksFirst`

The spec says “Delete asks to confirm.” The tile editor's Delete asks; the long-press menu deletes at once.
Combined with HUM-002 this is real data loss.

### HUM-009
**Welcome screen overflows on iPhone.** Medium · UI · *Found by:* screen tour (`01 welcome`)

The three 140 pt sample tiles plus spacing (≈450 pt) are wider than a 402 pt iPhone screen: the first and
last tiles are cut off, and the subtitle “A voice for your child in whole phrases…” is clipped at both
edges (it inherits the too-wide frame). Scale the sample keys to the width, or show two on iPhone.

### HUM-017
**Robotic voices are the top suggestions.** Medium · Bug · First run, Settings · *Found by:* screen tour

With only standard voices installed, first run offers Samantha, Fred, Junior, Kathy. Fred, Junior, Kathy,
Ralph and friends are old robotic MacinTalk voices that aren't flagged as novelty voices, so the filter
misses them. Settings lists ~15 voices before anything else, which pushes every other setting far down.
Also, no voice is marked as selected on the first-run voice step, so the parent can't tell which one is used.

### HUM-027
**After a big import nothing says where things went.** Medium · UX · *Found by:* by hand

After merging 115 boards, the editor shows the same Home with no message. The board menu (stack icon) is
one flat, unsorted list of 116 entries (two named “Home”) with no search. Show a summary banner after an
import (“Added 115 folders. Open …”) and group or search the board list.

### HUM-022
**Developer screens are shown to every parent.** Medium · Jargon · Settings · *Found by:* screen tour

Settings ends with “For developers”: “Tap-to-sound latency”, “AI helper (on this device)”, “AI helper
(Private Cloud Compute)”. The latency screen says “pre-rendered phrase”, “Taps that had to speak live”,
“Phrases waiting to render”, “Phrases in memory”, “Audio engine restarts”, “95th percentile”. The spec
calls it a *hidden* developer screen. Hide it behind a deliberate gesture (e.g. tap the version 7 times).
Keep the AI availability text, but move it next to the AI helper in plain words.

### HUM-023
**iCloud status shows developer instructions and raw errors.** Medium · Jargon · Setup & sharing ·
*Found by:* code (`SyncStatusRows`)

With sync on, parents see “How to see the records (for developers)” with CloudKit Console, zone
`com.apple.coredata.cloudkit.zone`, “QUERYABLE index on recordName”, and “Reason: <raw error>”. Move these
to a hidden developer screen and show a plain message (“iCloud isn't reachable right now. Your boards are
safe on this iPad.”).

### HUM-031
**AI availability is inconsistent.** Medium · Bug · AI helper · *Found by:* screen tour (`46–51`)

On the iOS 27 simulator, Settings says “Apple Intelligence is still getting ready… Try again later.” for
both modes, yet after “Turn on the helper” the helper shows the full “Suggest tiles” form instead of the
unavailable message. Also the toolbar's AI button shows on a device where it can't work yet. Check
on a real device (human test plan).

### HUM-036
**iPhone editor toolbar is hard to read.** Medium · UX · *Found by:* screen tour

On iOS 27 the toolbar shows icons only: “Done” is a bare checkmark (the code asks for title and icon), and
History, Setup & sharing and Settings sit behind “⋯”. A parent looking for “how do I get back to my child's
board” or “Settings” has to guess. Consider a text “Done” and a Settings item that's always visible.

## Low

### HUM-005
“Tiles are smaller than 88 points on this screen. Consider fewer rows or columns, or a folder.” Developer
wording (points, 88), and on iPhone 18 Pro it's truncated to “Consider fe…”. It also shows for the starter
board on every iPhone-size device, so it's noise. If kept, something like “Tiles are small on this screen.
Fewer rows or a folder makes them easier to tap.” *Found by:* `EditorUITests.testNoTechnicalSizeWarning`.

### HUM-007
On a phone page with 8 rows (a big imported board) the tiles are only ~70 pt tall, and the folder “Open” chip
plus the pencil cover the picture completely (“Nature”, “I Feel”). On iPhone the pencil badge (28 pt circle, top right) and the camera badge overlap every tile's emoji in the
editor; a third of the picture is hidden. *Found by:* screen tour.

### HUM-010
In a folder on iPhone, the band shows “‹ Home”, the title and the long help text in a narrow middle column
(9 lines), and the grid gets less than 60% of the screen. Even on Home the help text takes four lines. Show
the help once, or put it behind an “ⓘ”. *Found by:* screen tour (`26`, `30`).

### HUM-011
Import preview “What changes” list:
- Silent folder tiles show `Chat: “”`, `Needs: “”` (empty quotes). Show “opens a folder” instead.
- A label that ends in punctuation reads `I need a break.: “I need a break.”`.
- The list stops after 30 entries with no “and 1,836 more”.
*Found by:* screen tour (`60–62`).

### HUM-012
Settings → How it sounds footer: “…record tiles (edit a tile → Say it in your own voice).” The tile editor
button is “Record your voice”. *Found by:* code + screen tour.

### HUM-013
Settings → Folders and boards → Rows/Columns, and Home & folders → New folder, both allow 1 × 1. The grid
size sheet refuses fewer than 2 spots (“A board needs at least 2 spots.”). *Found by:* code.

### HUM-016
First-run voice step: the “Get a more natural voice” card's steps are cut off at “…such as Zoe, Ava or…”,
so the instructions never say where to tap. *Found by:* screen tour (`02 voice`).

### HUM-018
`TileEditorSheet.suggestLabel` keeps the first four words: “Let's go to the park!” → label “Let's go to
the”. Same in Paste phrases. A label that ends on “the”/“to”/“a” reads as a mistake; drop trailing
function words, or keep the whole short phrase. *Found by:* `EditorUITests.testLabelFollowsThePhraseAndSaveNeedsWords`.

### HUM-019
The emoji suggestion for “Let's go to the playground!” / “…park!” picks 🚪 (door) first, ahead of 🛝.
*Found by:* screen tour (`23`, `49`).

### HUM-020
AI helper intro: “Only your words and your tiles' text are us…” and “It only suggests. Nothing changes
until yo…” are truncated on iPhone. *Found by:* screen tour (`50`).

### HUM-021
History box buttons read “Said: Hi!. Say it again.”: a period is added after phrases that already end in
punctuation. *Found by:* `ChildModeUITests.testHistoryBox`.

### HUM-024
After shrinking a grid (or moving a tile into a full folder), the tray says “3 new tiles need a spot”. They
aren't new. “3 tiles need a spot” fits both cases. *Found by:* `EditorUITests.testShrinkingAsksAndUsesTheTray`.

### HUM-025
Settings → Tapping: “When a tile is tapped while talking: Start the new tap right away” and “Speak when the
finger: Touches the tile (fastest)”. Suggest “If a tile is tapped while Hum is talking: Stop and say the
new tile / Finish first / Say both” and “Speak when the finger touches / lifts off”. *Found by:* screen tour.

### HUM-026
History: the destructive “Clear” button shares one toolbar pill with “Done”. It asks first, but a quick
“Done” tap can land on it. Move Clear to the bottom of the list. *Found by:* screen tour (`43`).

### HUM-028
Tile editor with a photo: the button reads “Emoji…”, but choosing an emoji has no visible effect because a
photo always wins. Either hide it or say “Use an emoji instead” and remove the photo. *Found by:* code.

### HUM-029
Grid size quick sizes are 2 × 2 … 6 × 8; the starter's 5 × 4 isn't one, so no preset is selected when the
sheet opens. The steppers also allow 8 × 8 (the spec says up to 6 × 8). *Found by:* screen tour (`29`).

### HUM-032
iPhone-only wording: grid size footer “On iPhone, boards wider than 4 or taller than 8 use a phone layout
instead…”; editor page bar “Phone page 1 of 2”. Parents don't know what a “phone layout” is. Suggest
“On iPhone, big boards are split into pages. Tiles keep their places on iPad and Mac.” *Found by:* screen tour.

### HUM-034
Home & folders: the first section header “Home and folders” repeats the screen title. *Found by:* screen tour.

### HUM-035
`TileView` reads a tile with empty `spokenText` as “<label>, folder” whether or not it links to a board
(e.g. a recording-only tile). *Found by:* code.

### HUM-039
Home & folders → Food → rename to “Food and drink”. The folder screen title changes, but the tile on Home
that opens it still says “Food”. Renaming the *tile* does rename the folder (`FolderTests`); the other way
round doesn't. *Found by:* `BoardsUITests.testRenamingAFolderRenamesItsTile`.

### HUM-042
Setup & sharing → Export all boards: the save sheet took more than 10 seconds to appear in one run (and
appeared within 15 s in another), with no progress shown meanwhile. A parent will tap again. Show
“Preparing your boards…”. *Found by:* `ParentToolsUITests.testExportOpensTheSaveSheet`.

### HUM-045
On iPad Pro 13" every sheet (tile editor, Settings, Home & folders, Setup & sharing, Paste phrases) opens
as a ~420 pt form sheet in the middle of the screen with small text; Settings needs ~10 swipes. Consider
`.presentationSizing(.page)` for Settings and the tile editor on big iPads. *Found by:* screen tour on iPad.

### HUM-046
On iPad, the welcome screen's sample tiles, title and text sit in a small cluster in the middle, and the
grid-size step puts four small cards in a row at the top with the rest of the screen empty. Scale up for
regular width. *Found by:* screen tour on iPad.

### HUM-014
In the simulator panel, the first tap after launch or after a sheet closes is often ignored (seen on the
“⋯” menu, the board menu and the import Merge button). XCUITest taps were fine after fixing the menu query,
so this may be the panel, not Hum. Listed in the human test plan to check on a device.

---

## Fixes (2026-10-12)

Decisions from the owner: a merged file's Home becomes a folder on Home, like TD Snap's “import and
link” (HUM-001); the starter stays 5 × 4 and says so (HUM-003); a Home without protest tiles gets a
warning only (HUM-040); developer screens are removed, not hidden (HUM-022, HUM-023).

| Bug | Fix |
|-----|-----|
| HUM-001 | `MergePlanner` turns the file's Home into a folder named after the file and adds a folder tile in your Home's first empty spot (or the tray). The preview says so. |
| HUM-002 | Deleting a tile or folder registers its own undo (`BoardStore.change(_:undo:_:)`), which rebuilds it with the same ID, spot, picture and recording. SwiftData can't undo deletes. Because Undo makes new objects, older undo steps are forgotten after a delete (they'd point at the deleted ones and crash). |
| HUM-003 | The starter card says “A 5 × 4 board…” when a smaller size was picked, and every start choice sets the new-folder size to the picked grid. |
| HUM-004 | “Import a setup” no longer makes a Home first; setup finishes only when the import does. The file's own Home stays Home. |
| HUM-005 | Plain wording, wraps instead of truncating, and only shows below 64 pt (the starter on iPhone no longer triggers it). |
| HUM-006, 007 | On narrow edit tiles the badges sit in a strip above the picture, the camera reminder is hidden, and the folder's Open button moves to the top-left corner. |
| HUM-008 | The long-press “Delete tile” asks first, like the tile editor. |
| HUM-009 | The welcome tiles take the largest of three sizes that fits the width. |
| HUM-010 | On iPhone the band shows one short help line on Home and none in folders. |
| HUM-011 | Folder tiles read “Chat (opens a folder)”, a label equal to its phrase isn't repeated, and the list ends “and N more”. |
| HUM-012 | Footer says “Record your voice”. |
| HUM-013 | Every rows/columns stepper keeps at least 2 spots. |
| HUM-015 | Cancelling the camera keeps the current photo. |
| HUM-016 | The natural-voice card is never truncated. |
| HUM-017 | MacinTalk voices are filtered out, Eloquence voices go last, Settings shows the best 5 (plus the one in use) with “Show all”, and first run marks the voice in use. |
| HUM-018 | Labels drop a dangling small word: “Let's go to the park!” → “Let's go” (shared by the tile editor, Paste phrases and AI). |
| HUM-019 | “let's go”/“go” no longer suggest 🚪. |
| HUM-020 | The AI intro wraps. |
| HUM-021 | No added period after a phrase that already ends in punctuation. |
| HUM-022 | The “For developers” section and the latency screen are removed. |
| HUM-023 | iCloud shows plain status and one plain error line; the CloudKit steps moved to `docs/testing/ICLOUD.md`. |
| HUM-024 | “3 tiles need a spot”. |
| HUM-025 | “If a tile is tapped while Hum is talking: Stop and say the new tile / Finish first / Say both”; “Speak: As soon as a finger touches / When the finger lifts off”. |
| HUM-026 | “Clear history…” moved to the bottom of the list. |
| HUM-027 | After any import the editor shows a banner saying where things went, with Open. The board menu is Home first, then A→Z; Home & folders gets a search field past 12 boards. |
| HUM-028 | Choosing an emoji over a photo replaces the photo; the button says “Use an emoji instead…”. |
| HUM-029 | The board's own size is shown first among the quick sizes when it isn't one of them. |
| HUM-031 | The Settings AI rows that disagreed with the helper are gone (with HUM-022); the helper itself shows the plain reason when it can't run. |
| HUM-032 | “Page 1 of 2”, and “On iPhone, big boards are split into pages…”. |
| HUM-034 | The repeated header is gone. |
| HUM-035 | A silent tile is read as “folder” only when it opens one. |
| HUM-036 | “Done” is a word, and Settings sits next to it on iPhone. |
| HUM-037 | SVG pictures are drawn during the import's own progress bar, a few at a time, reusing web views, with a 10 s limit per picture. |
| HUM-038 | Replace everything undoes by putting the exported setup from just before back (and Redo replaces again). Background picture conversion and phone-page saves no longer land on the undo stack. The editor no longer reads tiles the undo deleted. |
| HUM-039 | Renaming a folder renames folder tiles that showed its old name. |
| HUM-040 | “Make Home board” warns when the board lacks Home's protest/regulation tiles (“Make Home anyway”). |
| HUM-041 | The tip is asked for 0.7 s after the editor appears, once the transition has settled. |
| HUM-043 | `TileLabel` sizes the font so the longest word fits, and keeps one-word labels on one line. |
| HUM-044 | The hold counts from the touch's own timestamp, so iPadOS holding back top-edge touches (~0.8 s) no longer stretches it; child mode also defers system top-edge gestures. |
| HUM-045 | Settings, the tile editor, Home & folders and Setup & sharing open page-sized on iPad. |
| HUM-046 | Bigger welcome tiles, title and grid choices on iPad and Mac. |
| HUM-047 | AI tiles stay on the board being edited unless the model names a folder that board opens (or Home, for protest tiles). A new folder gets a folder tile on that board, and the banner says where the tiles went. |
| HUM-048 | The renderer collects the whole phrase at the synthesizer's rate and resamples it once (`SampleBox`); the last 15 ms fade to silence; the clip cache moved to `v2`, so old clips render again. `SpeechCacheTests.chunkedSpeechResamplesWithoutEdgeGlitches` feeds a tone in 256-frame chunks and checks it comes out smooth. |
| HUM-014 | Not fixed: not reproduced by UI tests; check on a device. |

---

## Not bugs, but worth a look
- Setup & sharing says “.hum file” and “coding agent”. Fine for the agent section; consider “Hum file”
  in the export footer. (First run now says “A Hum file”.)
- The welcome progress bar is empty on the first screen and has no step labels.
- 115 boards import in about 20 seconds with a clear “Preparing pictures… 680 of 1581” progress bar. Good.
