"""Convert Clangen sprite sheets and flatten their JSON tables into KittyClan's bundle.

Run with Clangen's venv (needs Pillow):
    /path/to/clangen/.venv/bin/python tools/export_assets.py /path/to/clangen

Swift's JSON decoder does not preserve object key order, and Clangen's sprite
tables encode grid positions in key order, so every table is flattened to
ordered lists here.

iOS image decoding premultiplies alpha, which loses the exact straight-alpha
values the blend math depends on. Sheets are therefore stored as `.rgba`:
a little-endian UInt32 width and height, then raw-DEFLATE-compressed RGBA8.
"""
import json
import shutil
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

CLANGEN = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent.parent / "KittyClan" / "Resources" / "Sprites"
DICTS = CLANGEN / "sprites" / "dicts"

SHEETS = [
    "lineart", "heterochromiamask", "eyes", "pelt_parts_masks", "skin",
    "scars", "scars_missing_part", "patches_white_little", "patches_white_mid",
    "patches_white_high", "patches_white_mostly", "patches_points",
    "patches_vitiligo", "patches_tortie", "acc_plants", "acc_wilds",
    "lineart_sc", "lineart_df", "lineart_ur", "line_sc_overlay", "line_ur_underlay",
    "line_ur_overlay", "line_ur_gradient", "fademask", "fadestarclan", "fadedarkforest",
    "fadeunknownresidence",
]
SINGLE_SHEETS = [
    "lineart", "heterochromiamask", "lineart_sc", "lineart_df", "lineart_ur",
    "line_sc_overlay", "line_ur_underlay", "line_ur_overlay", "line_ur_gradient",
]
FADE_SHEETS = ["fademask", "fadestarclan", "fadedarkforest", "fadeunknownresidence"]
DATA_FILES = {
    "eyes": "eye_sprite_data",
    "pelt_parts_masks": "pelt_parts_masks_data",
    "skin": "skin_sprite_data",
    "scars": "scar_sprite_data",
    "scars_missing_part": "scar_missing_sprite_data",
    "patches_white_little": "white_patches_little_sprite_data",
    "patches_white_mid": "white_patches_mid_sprite_data",
    "patches_white_high": "white_patches_high_sprite_data",
    "patches_white_mostly": "white_patches_mostly_sprite_data",
    "patches_points": "white_patches_points_sprite_data",
    "patches_vitiligo": "white_patches_vitiligo_sprite_data",
    "patches_tortie": "tortie_patches_sprite_data",
    "acc_plants": "plant_sprite_data",
    "acc_wilds": "wild_sprite_data",
}


def load(name):
    with open(DICTS / f"{name}.json", encoding="utf-8") as f:
        return json.load(f)


def entries(sprite_list):
    """[(name, row, col, value)] in row-major order; value is set for dict rows."""
    out = []
    for row, items in enumerate(sprite_list):
        if isinstance(items, dict):
            out += [(n, row, col, v) for col, (n, v) in enumerate(items.items())]
        else:
            out += [(n, row, col, None) for col, n in enumerate(items)]
    return out


def write_rgba(png, out):
    image = Image.open(png).convert("RGBA")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    payload = compressor.compress(image.tobytes()) + compressor.flush()
    out.write_bytes(struct.pack("<II", *image.size) + payload)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "recipes").mkdir(parents=True)

    for sheet in SHEETS:
        write_rgba(CLANGEN / "sprites" / f"{sheet}.png", OUT / f"{sheet}.rgba")

    faded = [png for png in sorted((CLANGEN / "sprites" / "faded").glob("faded_*.png")) if "aprilfools" not in png.name]
    for png in faded:
        write_rgba(png, OUT / f"{png.stem}.rgba")

    sheets = {sheet: [["", 0, 0]] for sheet in SINGLE_SHEETS + [png.stem for png in faded]}
    sheets.update({sheet: [[str(i), 0, i] for i in range(3)] for sheet in FADE_SHEETS})
    body_parts = {}
    for sheet, data_name in DATA_FILES.items():
        rows = entries(load(data_name)["sprite_list"])
        sheets[sheet] = [[n, r, c] for n, r, c, _ in rows]
        if sheet in ("acc_plants", "acc_wilds"):
            body_parts.update({n: v for n, _, _, v in rows})

    eye_groups = {}
    for name, _, _, group in entries(load("eye_sprite_data")["sprite_list"]):
        eye_groups.setdefault(group, []).append(name)

    white_combos = load("white_patches_combos")
    white = {}
    for category in ("little", "mid", "high", "mostly"):
        combos = white_combos.get(category, {})
        white[category] = list(combos) + [n for n, *_ in sheets[f"patches_white_{category}"]]
    tortie_combos = load("tortie_patches_combos")

    index = {
        "poses": load("pose_sprite_data")["poses"],
        "sheets": sheets,
        "accessoryBodyParts": body_parts,
        "plants": [n for n, *_ in sheets["acc_plants"]],
        "wild": [n for n, *_ in sheets["acc_wilds"]],
        "eyeGroups": eye_groups,
        "whitePatches": white,
        "whitePatchCombos": {
            f"{cat}{name}": parts for cat, combos in white_combos.items() for name, parts in combos.items()
        },
        "tortiePatches": list(tortie_combos) + [n for n, *_ in sheets["patches_tortie"]],
        "tortiePatchCombos": tortie_combos,
        "points": [n for n, *_ in sheets["patches_points"]],
        "vitiligo": [n for n, *_ in sheets["patches_vitiligo"]],
        "skins": [n for n, *_ in sheets["skin"]],
        "scars": [n for n, *_ in sheets["scars"]],
        "missingPartScars": [n for n, *_ in sheets["scars_missing_part"]],
        "generation": load("generation_group_data")["pelts"],
        "peltToRecipe": load("pelt_to_recipe"),
        "palettes": load("pelt_color_palettes"),
        "tint": load("tint"),
        "whitePatchesTint": load("white_patches_tint"),
    }
    with open(OUT / "index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(",", ":"))

    # Round-trip through Python's parser so duplicate keys resolve the way Clangen sees them.
    for recipe in (DICTS / "pelt_recipes").glob("*.json"):
        with open(recipe, encoding="utf-8") as f:
            data = json.load(f)
        with open(OUT / "recipes" / recipe.name, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1)
    shutil.copy(CLANGEN / "resources" / "lang" / "en" / "names.json", OUT / "names.json")
    export_text()
    export_camps()
    afterlife = OUT.parent / "Afterlife"
    afterlife.mkdir(exist_ok=True)
    for name in ("starclanbg", "darkforestbg", "urbg"):
        shutil.copy(CLANGEN / "resources" / "images" / f"{name}.png", afterlife / f"{name}.png")

    golden = OUT.parent.parent.parent / "KittyClanTests" / "Golden"
    for png in golden.glob("*.png"):
        write_rgba(png, png.with_suffix(".rgba"))
    print(f"exported {len(SHEETS)} sheets to {OUT}")


def export_text():
    """Copy the event text KittyClan narrates with. English files wrapped in {"en": ...} are unwrapped."""
    lang = CLANGEN / "resources" / "lang" / "en"
    text = OUT.parent / "Text"
    if text.exists():
        shutil.rmtree(text)
    files = {
        "ceremonies": sorted((lang / "events" / "ceremonies").glob("*.json")),
        "death": [lang / "events" / "death" / "general.json", lang / "events" / "death" / "forest.json"],
        "misc": [lang / "events" / "misc" / "general.json", lang / "events" / "misc" / "forest.json"],
        "": [
            lang / "pronouns.en.json",
            lang / "conditions" / "pregnancy.json",
            lang / "conditions" / "pregnancy.en.json",
            CLANGEN / "resources" / "dicts" / "traits" / "trait_ranges.json",
        ],
    }
    rel = lang / "events" / "relationship_events"
    for kind in ("normal_interactions", "group_interactions", "joining_interactions"):
        for path in sorted((rel / kind).rglob("*.json")):
            folder = str(path.parent.relative_to(lang / "events"))
            files.setdefault(folder, []).append(path)
    files["relationship_events"] = [rel / "become_mates.json", rel / "become_mates_poly.json", rel / "breakup_mates.json"]
    dicts = CLANGEN / "resources" / "dicts" / "conditions"
    cond = lang / "conditions"
    files["conditions"] = [
        dicts / "injuries.json", dicts / "illnesses.json", dicts / "permanent_conditions.json", dicts / "illnesses_seasons.json",
        cond / "injuries.en.json", cond / "illnesses.en.json", cond / "permanent_conditions.en.json",
        *sorted((cond / "condition_got_strings").glob("*.json")),
        *sorted((cond / "healed_and_death_strings").glob("*.json")),
        *sorted((cond / "risk_strings").glob("*.json")),
    ]
    files["herbs"] = [
        CLANGEN / "resources" / "dicts" / "herb_info.json",
        cond / "herbs.en.json",
        lang / "screens" / "med_den_messages.json",
    ]
    files["injury"] = [lang / "events" / "injury" / "general.json", lang / "events" / "injury" / "forest.json"]
    patrols = lang / "patrols"
    files["patrols"] = [
        patrols / "new_cat.json", patrols / "new_cat_welcoming.json", patrols / "new_cat_hostile.json",
        patrols / "other_clan.json", patrols / "other_clan_hostile.json", patrols / "other_clan_ally.json",
    ]
    events = lang / "events"
    files["war"] = [events / "war.json"]
    files["leader_den/success"] = sorted((events / "leader_den" / "success").glob("*.json"))
    files["leader_den/fail"] = sorted((events / "leader_den" / "fail").glob("*.json"))
    files["new_cat"] = [events / "new_cat" / "general.json", events / "new_cat" / "forest.json"]
    files["outsider_deaths"] = [events / "death" / "outsider_deaths" / "outsider_deaths.json"]
    files["patrols/general"] = sorted((patrols / "general").glob("*.json"))
    for folder in ("hunting", "border", "training", "med"):
        files[f"patrols/forest/{folder}"] = sorted((patrols / "forest" / folder).glob("*.json"))
    files[""].append(lang / "relationships.en.json")
    files[""].append(lang / "cat" / "skills.en.json")
    thoughts = lang / "thoughts"
    for path in sorted(thoughts.rglob("*.json")):
        files.setdefault(str(path.parent.relative_to(lang)), []).append(path)
    files["afterlife"] = [
        events / "lead_ceremony_sc.json", events / "lead_ceremony_df.json",
        lang / "cat" / "afterlife.en.json", lang / "cat" / "backstories.en.json",
        lang / "cat" / "history.en.json",
    ]

    with open(patrols / "prey_text_replacements.json", encoding="utf-8") as f:
        prey = json.load(f)
    forest_prey = {k: v for k, v in prey["abbreviations"].items() if k.startswith("f_")}
    (text / "patrols").mkdir(parents=True, exist_ok=True)
    with open(text / "patrols" / "prey.json", "w", encoding="utf-8") as f:
        json.dump({abbr: prey[key] for abbr, key in forest_prey.items()}, f, ensure_ascii=False)

    for folder, paths in files.items():
        (text / folder).mkdir(parents=True, exist_ok=True)
        for path in paths:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and list(data) == ["en"]:
                data = data["en"]
            with open(text / folder / path.name, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False)

    export_patrol_art([path for folder, paths in files.items() if folder.startswith("patrols") for path in paths])


def export_camps():
    """Copy the forest camp backgrounds and Clangen's forest camp layouts."""
    out = OUT.parent / "Camps"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for png in sorted((CLANGEN / "resources" / "images" / "camp_bg" / "forest").glob("*.png")):
        shutil.copy(png, out / png.name)
    with open(CLANGEN / "resources" / "placements.json", encoding="utf-8") as f:
        placements = json.load(f)
    layouts = {key: value for key, value in placements.items() if key.startswith("Forest") or key == "default"}
    with open(out / "layouts.json", "w", encoding="utf-8") as f:
        json.dump(layouts, f)


def export_patrol_art(patrol_files):
    """Copy the art the bundled patrols reference, with lowercased names so lookups ignore case."""
    art = CLANGEN / "resources" / "images" / "patrol_art"
    out = OUT.parent / "PatrolArt"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    available = {str(path.relative_to(art)).lower()[:-4]: path for path in art.rglob("*") if path.suffix.lower() == ".png"}

    wanted = {"hunt_general_intro", "bord_general_intro", "train_general_intro", "med_general_intro"}
    def collect(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("patrol_art", "patrol_art_clean", "outcome_art", "outcome_art_clean") and isinstance(value, str):
                    wanted.add(value.lower())
                else:
                    collect(value)
        elif isinstance(node, list):
            for item in node:
                collect(item)
    for path in patrol_files:
        with open(path, encoding="utf-8") as f:
            collect(json.load(f))

    copied = 0
    for name in sorted(wanted):
        source = available.get(name)
        if source is None or source.stat().st_size == 0:
            continue
        target = out / (name.replace("/", "__") + ".png")
        shutil.copy(source, target)
        copied += 1
    print(f"copied {copied} of {len(wanted)} patrol art references")


main()
