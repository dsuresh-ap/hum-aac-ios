# Copyright 2026 The Hum Authors
# SPDX-License-Identifier: Apache-2.0
"""Writes mini.sps: a tiny made-up TD Snap page set for SnapImporterTests.

It uses Snap's real table layout but only invented content and drawings (no Snap symbols).
Run from this folder:  python3 make-mini-sps.py
"""
import json
import os
import sqlite3
import struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mini.sps")

HOME = "11111111-0000-4000-8000-000000000001"
TOPIC = "11111111-0000-4000-8000-000000000002"
TOPIC2 = "11111111-0000-4000-8000-000000000003"
KEYBOARD = "11111111-0000-4000-8000-000000000004"
SCALE = "11111111-0000-4000-8000-000000000005"
BIG = "11111111-0000-4000-8000-000000000006"
SNAP_HOME_ALIAS = "3acaf8df-164b-4c93-a40e-356c547e1d84"  # Snap's Home buttons point here


def wmf_polygon(points):
    """A placeable WMF with one red polygon (big enough to need SQLite overflow pages)."""
    records = b""

    def record(function, *words):
        return struct.pack("<IH", 3 + len(words), function) + struct.pack(f"<{len(words)}h", *words)

    records += record(0x020B, 0, 0)  # SETWINDOWORG y, x
    records += record(0x020C, 100, 200)  # SETWINDOWEXT y, x
    records += struct.pack("<IHH", 7, 0x02FC, 0) + bytes([0xD0, 0x20, 0x30, 0]) + struct.pack("<H", 0)  # red brush
    records += record(0x012D, 0)  # SELECTOBJECT 0
    flat = [v for p in points for v in p]
    records += record(0x0324, len(points), *flat)  # POLYGON
    records += struct.pack("<IH", 3, 0)  # EOF
    header = struct.pack("<HHHIHIH", 1, 9, 0x0300, (18 + len(records)) // 2, 1, 0, 0)
    placeable = struct.pack("<IHhhhhHI", 0x9AC6CDD7, 0, 0, 0, 200, 100, 1440, 0)
    placeable += struct.pack("<H", 0)  # checksum (not checked)
    return placeable + header + records


def emf_curve():
    """An EMF with one blue filled Bézier path, drawn far inside a big frame."""
    def rec(kind, payload):
        return struct.pack("<II", kind, 8 + len(payload)) + payload

    body = rec(39, struct.pack("<IIII", 1, 0, 0x00FF3020, 0))  # brush 1: BGR → #2030ff
    body += rec(37, struct.pack("<I", 1))
    body += rec(59, b"")
    body += rec(27, struct.pack("<ii", 1000, 1000))
    pts = [(1100, 900), (1300, 900), (1400, 1000), (1300, 1200), (1100, 1200), (1000, 1000)]
    body += rec(88, struct.pack("<iiii", 0, 0, 0, 0) + struct.pack("<I", len(pts)) + b"".join(struct.pack("<hh", *p) for p in pts))
    body += rec(60, b"")
    body += rec(62, struct.pack("<iiii", 0, 0, 0, 0))
    body += rec(14, struct.pack("<III", 0, 16, 20))
    header_payload = struct.pack("<iiii", 0, 0, 5000, 5000) + struct.pack("<iiii", 0, 0, 5000, 5000)
    header_payload += b" EMF" + struct.pack("<IIIHH", 0x10000, 0, 0, 0, 0)
    header_payload = header_payload.ljust(100, b"\0")
    return rec(1, header_payload) + body


PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000"
                    "1f15c4890000000d49444154789c6360000002000100e221bc330000000049454e44ae426082")

if os.path.exists(OUT):
    os.remove(OUT)
db = sqlite3.connect(OUT)
db.execute("pragma page_size=1024")
db.executescript("""
CREATE TABLE PageSetProperties (Id integer PRIMARY KEY, UniqueId VARCHAR(36), DefaultHomePageUniqueId VARCHAR(36),
  FriendlyName VARCHAR, GridDimension VARCHAR);
CREATE TABLE "Page" ( "Id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "UniqueId" varchar(36), "Title" varchar, "PageType" integer);
CREATE TABLE "PageLayout" ( `Id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `PageLayoutSetting` varchar, `PageId` integer );
CREATE TABLE ElementReference( Id integer primary key autoincrement not null , ElementType integer , BackgroundColor integer , PageId integer );
CREATE TABLE ElementPlacement( Id integer primary key autoincrement not null , GridPosition varchar ,
  GridSpan varchar not null default('1,1') , Visible integer , ElementReferenceId integer , PageLayoutId integer );
CREATE TABLE Button( Id integer primary key autoincrement not null, Label varchar, Message varchar, ContentType integer,
  UniqueId varchar(36), LibrarySymbolId integer, PageSetImageId integer, ElementReferenceId integer );
CREATE TABLE 'ButtonPageLink' ( 'Id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 'ButtonId' INTEGER NOT NULL,
  'PageUniqueId' varchar(36) NOT NULL, FOREIGN KEY('ButtonId') REFERENCES 'Button'('Id') ON DELETE CASCADE);
CREATE TABLE "CommandSequence"( "Id" integer primary key autoincrement not null , "SerializedCommands" varchar , "ButtonId" integer );
CREATE TABLE "PageSetData"( "Id" integer primary key autoincrement not null , "Identifier" varchar , "Data" blob , "RefCount" integer DEFAULT 0);
""")
# A column added later, like Snap's own schema upgrades: older rows have no value for it.
db.execute("ALTER TABLE Button ADD COLUMN SymbolColorDataId integer DEFAULT(0)")
db.execute("INSERT INTO PageSetProperties VALUES (1, 'aaaaaaaa-0000-4000-8000-000000000000', ?, 'Mini set', '6,3')", (HOME,))

images = {}
for name, data in [("wmf", wmf_polygon([(10 + i % 180, 10 + (i * 7) % 80) for i in range(400)])),
                   ("emf", emf_curve()), ("png", PNG)]:
    images[name] = db.execute("INSERT INTO PageSetData (Identifier, Data) VALUES (?, ?)", (f"IMG:{name}", data)).lastrowid

pages = {}
for uid, title, setting in [(HOME, "Home page", "6,3,True,0"), (TOPIC, "Protests", "6,3,True,0"),
                            (TOPIC2, "Protests 2", "6,3,True,0"), (KEYBOARD, "Keyboard (ABC)", "10,5,True,0"),
                            (SCALE, "Rating scale", "8,3,True,0"), (BIG, "Big scale", "13,1,True,0")]:
    pid = db.execute("INSERT INTO Page (UniqueId, Title, PageType) VALUES (?, ?, 1)", (uid, title)).lastrowid
    lid = db.execute("INSERT INTO PageLayout (PageLayoutSetting, PageId) VALUES (?, ?)", (setting, pid)).lastrowid
    pages[uid] = (pid, lid)
serial = 0


def button(page, pos, label, *, commands=(), message=None, link=None, image=None, library=0, color=-132102,
           visible=1, span="1,1", content_type=6):
    global serial
    serial += 1
    pid, lid = pages[page]
    ref = db.execute("INSERT INTO ElementReference (ElementType, BackgroundColor, PageId) VALUES (0, ?, ?)", (color, pid)).lastrowid
    db.execute("INSERT INTO ElementPlacement (GridPosition, GridSpan, Visible, ElementReferenceId, PageLayoutId) VALUES (?, ?, ?, ?, ?)",
               (pos, span, visible, ref, lid))
    uid = f"22222222-0000-4000-8000-{serial:012d}"
    bid = db.execute("INSERT INTO Button (Label, Message, ContentType, UniqueId, LibrarySymbolId, PageSetImageId, ElementReferenceId)"
                     " VALUES (?, ?, ?, ?, ?, ?, ?)", (label, message, content_type, uid, library, image or 0, ref)).lastrowid
    db.execute("INSERT INTO CommandSequence (SerializedCommands, ButtonId) VALUES (?, ?)",
               (json.dumps({"$type": "1", "$values": [{"$type": c} for c in commands]}), bid))
    if link:
        db.execute("INSERT INTO ButtonPageLink (ButtonId, PageUniqueId) VALUES (?, ?)", (bid, link))
    return uid


SPEAK, OPEN, BACK, GO_HOME = "3", "2", "4", "5"
# Home: column 0 holds real tiles, so it keeps all 6 columns.
button(HOME, "0,0", "Stop/No", commands=[OPEN], link=TOPIC, image=images["wmf"], color=-6696232)
button(HOME, "0,1", "Keyboard", commands=["17"], link="99999999-0000-4000-8000-000000000000")
button(HOME, "1,0", "outside", commands=[SPEAK], message="Let's go outside!", image=images["png"])
button(HOME, "2,0", "apple", commands=[SPEAK], library=4242)
button(HOME, "3,0", "secret", commands=[SPEAK], visible=0)
button(HOME, "4,0", "Rating", commands=[OPEN], link=SCALE)
button(HOME, "5,0", "Big", commands=[OPEN], link=BIG)
button(HOME, "5,4", "Keys", commands=[OPEN], link=KEYBOARD)
button(HOME, "1,1", "Dashboard", commands=["6"])
# Protests: Snap's navigation column (Back / Next page / Home) on the left.
button(TOPIC, "0,0", "Back", commands=[BACK], color=16777215)
button(TOPIC, "0,1", "Next page", commands=[OPEN], link=TOPIC2, color=16777215)
button(TOPIC, "0,2", "Home", commands=[GO_HOME], link=SNAP_HOME_ALIAS, color=16777215)
button(TOPIC, "1,0", "stop it", commands=[SPEAK], image=images["emf"])
button(TOPIC, "5,4", "too loud", commands=[SPEAK], message="it's too loud")
button(TOPIC2, "0,0", "Back", commands=[BACK])
button(TOPIC2, "0,2", "Home", commands=[GO_HOME], link=SNAP_HOME_ALIAS)
button(TOPIC2, "1,0", "no thank you", commands=[SPEAK])
# A rating scale with big gaps between its buttons.
button(SCALE, "0,0", "Back", commands=[BACK])
for i, col in enumerate([1, 4, 7]):
    button(SCALE, f"{col},2", str(i + 1), commands=[SPEAK], span="3,1")
for col in range(13):
    button(BIG, f"{col},0", str(col), commands=[SPEAK])
button(KEYBOARD, "0,0", "q", commands=[SPEAK], content_type=2)
# Unplaced filler buttons, so the Button table needs interior b-tree pages.
for i in range(300):
    db.execute("INSERT INTO Button (Label, Message, ContentType, UniqueId) VALUES (?, ?, 6, ?)",
               (f"filler {i}", "x" * 40, f"33333333-0000-4000-8000-{i:012d}"))
db.commit()
db.execute("VACUUM")
db.close()
print("wrote", OUT, os.path.getsize(OUT), "bytes")
