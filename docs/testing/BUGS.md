# Hum bug log (end-to-end test pass, 2026-10-11)

Found while walking every screen on the iOS 27 simulator (iPhone 18 Pro, iPhone 18 Pro Max, iPad Pro 13-inch) with the UI
tests in `HumUITests/` and by hand. A bug that a UI test reproduces is wrapped in
`XCTExpectFailure("HUM-0xx …")` in that test: the suite stays green, and the test starts failing
(“expected failure but none recorded”) once the bug is fixed. That's the cue to remove the wrapper.

**Severity:** Critical (data loss, or the child loses access to words) · High (a main flow is broken
or misleading) · Medium (works, but confusing or against the spec) · Low (polish).
**Kind:** Bug · UI (layout/sizing) · Text (wording) · Jargon (words a parent shouldn't see) · A11y.
**Found by:** the UI test that shows it, “code” (read in the source, not run), or “by hand”.

| ID | Sev | Kind | Screen | Summary |
|----|-----|------|--------|---------|
| [HUM-001](#hum-001) | Critical | Bug | Import | Merging a whole setup strands its Home: all imported boards (and its protest tiles) become unreachable |
| [HUM-002](#hum-002) | Critical | Bug | Editor | Undo after deleting a tile doesn't bring it back; the tile is lost |
| [HUM-037](#hum-037) | High | Bug | Import (iOS) | Imported SVG symbols stay blank for minutes after import (1 of ~40 appeared in 90 s) |
| [HUM-038](#hum-038) | High | Bug | Import | Undo after “Replace everything” doesn't bring the old boards back |
| [HUM-004](#hum-004) | High | Bug | First run | “Import a setup” makes an empty Home first; cancelling leaves a blank board, importing hits HUM-001 |
| [HUM-015](#hum-015) | High | Bug | Tile editor | Cancelling the camera deletes the tile's existing photo |
| [HUM-003](#hum-003) | Medium | Bug | First run | The grid size picked in setup is ignored for the starter board |
| [HUM-006](#hum-006) | Medium | UI | Editor (iPhone) | Tapping a folder tile opens the folder instead of editing it |
| [HUM-008](#hum-008) | Medium | Bug | Editor | “Delete tile” in the long-press menu deletes without asking |
| [HUM-009](#hum-009) | Medium | UI | Welcome (iPhone) | Sample tiles are wider than the screen; the subtitle is cut off on both sides |
| [HUM-017](#hum-017) | Medium | Bug | First run, Settings | Robotic legacy voices (Fred, Junior, Kathy, Ralph…) are offered as top picks |
| [HUM-027](#hum-027) | Medium | UX | Import, Editor | After a big import nothing says where the boards went; the board menu is a flat list of 116 |
| [HUM-022](#hum-022) | Medium | Jargon | Settings | “For developers” section and latency screen are visible to every parent |
| [HUM-023](#hum-023) | Medium | Jargon | Setup & sharing | iCloud rows show CloudKit console steps and raw error text |
| [HUM-031](#hum-031) | Medium | Bug | AI helper | Settings says the AI isn't ready, but the helper shows the “Suggest tiles” form anyway |
| [HUM-036](#hum-036) | Medium | UX | Editor (iPhone) | “Done” is a bare checkmark; History, Setup & sharing and Settings hide in “⋯” |
| [HUM-040](#hum-040) | Medium | Bug | Home & folders | “Make Home board” on a board without protest tiles gives no warning |
| [HUM-041](#hum-041) | Medium | Bug | Editor | The one-time Guided Access tip sometimes never appears |
| [HUM-043](#hum-043) | Medium | UI | Child, Editor | Labels break in the middle of words on narrow tiles (“Clothin/g”, “Weathe/r”) |
| [HUM-044](#hum-044) | Medium | Bug | Child (iPad) | The 3-second lock needs a much longer hold on iPad (3.5 s fails, 6 s works) |
| [HUM-005](#hum-005) | Low | Jargon/UI | Editor | “Tiles are smaller than 88 points…” is developer wording, and cut off |
| [HUM-007](#hum-007) | Low | UI | Editor (iPhone) | Pencil and camera badges cover the tile's picture |
| [HUM-010](#hum-010) | Low | UI | Editor (iPhone) | Inside a folder, the help text is squeezed into a 9-line column; it takes a quarter of the screen |
| [HUM-011](#hum-011) | Low | Text | Import preview | `Chat: “”` for folders, `I need a break.: “I need a break.”`, list silently stops at 30 |
| [HUM-012](#hum-012) | Low | Text | Settings | Footer points to “Say it in your own voice”; the button is called “Record your voice” |
| [HUM-013](#hum-013) | Low | Bug | Settings, Home & folders | New-board size can be set to 1 × 1, which the grid sheet says is too small |
| [HUM-016](#hum-016) | Low | UI | First run (voice) | The natural-voice help card is cut off with “…” |
| [HUM-018](#hum-018) | Low | Text | Tile editor, Paste phrases | Suggested label stops after four words: “Let's go to the” |
| [HUM-019](#hum-019) | Low | Text | Tile editor, Paste phrases | First emoji idea for “Let's go to the park/playground” is a door 🚪 |
| [HUM-020](#hum-020) | Low | UI | AI helper | Intro bullet points are cut off (“…are us…”, “…until yo…”) |
| [HUM-021](#hum-021) | Low | A11y | Child (history box) | VoiceOver reads “Said: Hi!. Say it again.” |
| [HUM-024](#hum-024) | Low | Text | Editor tray | Tiles moved off a shrunk board are called “new tiles” |
| [HUM-025](#hum-025) | Low | Text | Settings | “Start the new tap right away”, “Speak when the finger” are hard to read |
| [HUM-026](#hum-026) | Low | UX | History | “Clear” sits right next to “Done” |
| [HUM-028](#hum-028) | Low | UX | Tile editor | Picking an emoji while a photo is set does nothing visible |
| [HUM-029](#hum-029) | Low | UX | Grid size | The board's current size (5 × 4 starter) isn't a quick size, so nothing is selected |
| [HUM-032](#hum-032) | Low | Jargon | Grid size, Editor | “phone layout”, “wider than 4 or taller than 8”, “Phone page 1 of 2” |
| [HUM-034](#hum-034) | Low | Text | Home & folders | Section header “Home and folders” repeats the title |
| [HUM-035](#hum-035) | Low | A11y | Child | A tile with no words is read as “<label>, folder” even when it isn't a folder |
| [HUM-039](#hum-039) | Low | Bug | Home & folders | Renaming a folder doesn't rename the tile that opens it |
| [HUM-042](#hum-042) | Low | UX | Setup & sharing | Export can take over 10 s with no “preparing…” feedback |
| [HUM-045](#hum-045) | Low | UI | All sheets (iPad) | Sheets are small form sheets on a 13" iPad; Settings needs lots of scrolling |
| [HUM-046](#hum-046) | Low | UI | First run (iPad) | Welcome and grid steps use a small block in the middle of a big screen |
| [HUM-014](#hum-014) | ? | Bug? | Editor | First tap on “⋯” (and after a sheet closes) sometimes ignored; simulator panel only so far |

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

### HUM-004
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

## Not bugs, but worth a look
- Setup & sharing says “.hum file” and “coding agent”. Fine for the agent section; consider “Hum file”
  in the export footer.
- The welcome progress bar is empty on the first screen and has no step labels.
- 115 boards import in about 20 seconds with a clear “Preparing pictures… 680 of 1581” progress bar. Good.
