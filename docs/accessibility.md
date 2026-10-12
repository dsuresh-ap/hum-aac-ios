# Accessibility check for the App Store labels

App Store Connect asks which accessibility features Hum supports. **Declare only a feature marked
Pass.** See [`release-actions.md`](release-actions.md), Task 6.

**Status: not tested yet.** This table was started without a simulator. Nothing below is a Pass until
someone tests it on an iOS 27 simulator (iPhone and iPad) with Accessibility Inspector, and on the Mac.

Screens to test for each feature: the child's board, the tile editor, Settings (and About Hum), and
the first run.

| Feature | iPhone | iPad | Mac | Notes |
|---|---|---|---|---|
| VoiceOver | Not tested | Not tested | Not tested | Tiles read "label" (child) or "label. Says: phrase" (editor). Icon-only parent buttons got names in Task 5. |
| Voice Control | Not tested | Not tested | Not tested | Say "Show names" and check every button has a name you can say. |
| Larger Text | Not tested | Not tested | Not tested | Test at the largest accessibility size. The first run now passes at Accessibility XXXL on iPhone and iPad simulators (UI test `testStartFootnoteAtTheLargestTextSize`): the voice and grid steps used to push Next off-screen and now scroll. The other screens are still to check. |
| Dark Interface | Not tested | Not tested | Not tested | Settings → Tiles → Appearance, and the system setting. |
| Differentiate Without Color Alone | Not tested | Not tested | Not tested | Tile function is shown by colour, but every tile also has its words, so no meaning is in colour only. Check the editor's hidden-tile and selected states. |
| Sufficient Contrast | Not tested | Not tested | Not tested | Tiles read `colorSchemeContrast`. Check secondary text in Settings and the editor with Increase Contrast on and off. |
| Reduced Motion | Not tested | Not tested | Not tested | Tile press and release have no animation when Reduce Motion is on (release fixed in this change). The lock's 3-second ring still fills: it shows progress, it isn't decoration. |

How to fill it in: change "Not tested" to **Pass** or **Fail**, and write what failed in Notes. Fix
small problems; list big ones in [`testing/BUGS.md`](testing/BUGS.md).

## Checked so far (2026-10-12)

Not enough for a Pass on any row yet, but these are confirmed:

- First run at Accessibility XXXL (iPhone 18 Pro and iPad Pro 13" simulators, iOS 27): every step can be
  finished, and the footnote can be scrolled to. Fixed in this check (Next was off-screen).
- Mac, Accessibility tree: the About Hum row and the four About links ("Privacy policy", "Help and
  support", "Source code", "Licence (Apache-2.0)") have clear names.
