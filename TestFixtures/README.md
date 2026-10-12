# Test fixtures

`Local/` is ignored by git. Put real families' setups there for the big-import UI tests; they may contain
personal photos and words, so they never go in this public repo.

- `Local/Express2-v2.hum`: a 115-board, 1,866-tile setup (6 × 8 Home, ~1,580 pictures, mostly SVG) used by
  `HumUITests/ImportUITests.swift` and `ScreenTourTests.testTourBigImport`. Tests that need it are skipped
  when it's missing.

The simulator reads these files straight from the Mac, using a path worked out from the test source file.
