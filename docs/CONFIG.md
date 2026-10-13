# Hum config format (`hum.json` and `.hum`)

Hum's whole setup (boards, tiles, settings and photos) is one open, documented file. You can write
or edit it in any text editor, or ask a coding agent (for example Claude Code on a Mac) to do it,
then import it into Hum.

- **`hum.json`** is plain JSON: boards, tiles and settings.
- **`.hum`** is a zip with `hum.json` at the top and a `media/` folder for photos and recordings.
- The formal definition is the JSON Schema at [`schema/hum.schema.json`](../schema/hum.schema.json).
- Agents: also read [`AGENTS.md`](../AGENTS.md).

## Why the rules matter (GLP in one minute)

Many autistic children are **Gestalt Language Processors (GLPs)**. They learn language in whole
chunks, often from songs, shows or things adults say ("let's get out of here!", "to infinity and
beyond!"). A whole chunk can carry a whole meaning: "let's get out of here!" may mean "I want to
leave". In the Natural Language Acquisition framework, children use whole gestalts first, then mix
parts of them, then single words, then their own grammar.

So in Hum:

| Rule | Why |
|---|---|
| **One tile = one whole gestalt** | Splitting a gestalt into words removes its meaning for a Stage 1–2 GLP. |
| **Positions never change on their own** | Children find tiles by where they are (motor planning), not by reading. |
| **Protest tiles are as big as request tiles** | "No" and "stop" are real communication. The parent decides which boards they go on. |
| **No praise or reward phrases** | Hum is the child's voice, not a behavior tool. |

## The format

```jsonc
{
  "formatVersion": 1,                 // required, always 1 for now
  "name": "Maya's boards",            // optional
  "boards": [
    {
      "id": "a6f3…",                  // UUID, stable forever
      "name": "Home",
      "rows": 3, "columns": 4,        // rows 1–20, columns 1–8; a taller board scrolls down
      "isHome": true,                 // exactly one Home in a full setup
      "tiles": [
        {
          "id": "0c1e…",              // UUID, stable forever
          "label": "more",            // short text on the tile (optional; defaults to spokenText)
          "spokenText": "Let's do it again!",   // what it says: one whole gestalt
          "row": 0, "column": 0,      // counting from 0; one tile per spot
          "function": "request",      // protest | request | connection | comment | regulation | other
          "color": "#CFE6CC",         // optional; otherwise from function
          "linkedBoardID": "…",       // optional: makes it a folder that opens this board
                                      // (a folder may have "spokenText": "" to just open silently)
          "hidden": false,            // optional: hidden tiles keep their (empty) spot
          "image": "media/more.jpg",  // optional, inside a .hum (JPEG, PNG, HEIC or SVG; resized on import)
          "audio": "media/more.m4a",  // optional parent recording (keeps real intonation)
          "symbol": "🔁",              // optional emoji placeholder
          "imageCredit": "Mulberry Symbols by Steve Lee …"  // optional: credit and licence of the picture
        }
      ]
    }
  ],
  "settings": {                       // optional
    "voice": { "identifier": "com.apple.voice.premium.en-US.Zoe", "rate": 0.5, "pitch": 1, "volume": 1 },
    "showLabels": true, "labelPosition": "bottom",
    "sentenceStrip": false, "appearance": "system",
    "retrigger": "restart", "activation": "touchDown"
  }
}
```

`imageCredit` is filled in by Hum when a parent picks a symbol from ARASAAC or Mulberry: their
licences ask for the credit to travel with the picture. Keep it when you copy the tile or its
picture. If any tile has one, an exported `.hum` also has a `CREDITS.txt` at the top that lists each
credit once. Hum makes that file again on every export and ignores it on import.

Unknown fields are allowed and **kept**: Hum writes them back out on export. iCloud sync and AI are
intentionally not in the file; only a parent can switch those on, inside the app.

## Importing: what happens to the boards already in Hum

Hum always shows a preview first, for example *"3 new tiles, 2 changed tiles, 0 removed. No tiles
will move."*

- **Merge** (default): tiles and boards are matched by `id`. Matching tiles get the new words, label,
  color and media, but **keep their spot**. New tiles go to the spot the file asks for if it's free;
  otherwise they wait in a "needs a spot" tray for the parent. Nothing is deleted, and grids only grow.
- **Replace everything**: the file becomes the whole setup. Hum makes a backup first and asks to confirm.

## Tools

```bash
# Check a file (exit code 1 if it has errors)
swift run --package-path Packages/HumConfig hum-config validate my-setup/hum.json

# Bundle hum.json + media/ into one file to AirDrop or put in iCloud Drive
swift run --package-path Packages/HumConfig hum-config pack my-setup my-setup.hum

# Unpack an exported setup to edit it
swift run --package-path Packages/HumConfig hum-config unpack exported.hum my-setup
```

Errors are written for people, e.g. `Tile 'snack' has no words to say.`

## Examples

| File | What it shows |
|---|---|
| [`examples/starter.hum.json`](../examples/starter.hum.json) | The starter board Hum ships with: 18 whole-gestalt tiles grouped by function, protest tiles on Home. |
| [`examples/food.hum.json`](../examples/food.hum.json) | A single "Food" board using whole "Let's have ___!" phrases (one complete phrase per tile). |
| [`examples/linked-boards.hum.json`](../examples/linked-boards.hum.json) | A Home board with folder tiles that open Food, Play and Outside sub-boards; protest tiles stay on Home. |

## Asking a coding agent to make a board

Example prompt for Claude Code (or any agent) in a clone of this repo:

> Read AGENTS.md and docs/CONFIG.md. My daughter says "all aboard!" when she wants to go somewhere and
> "the end!" when she's done. Add a "Trains" board linked from Home to my exported setup in
> `my-setup/hum.json`. Keep every existing tile where it is. Validate with hum-config, then pack it
> to `my-setup.hum`.

Then open `my-setup.hum` on the iPad (AirDrop, Files or iCloud Drive) and check the preview.
