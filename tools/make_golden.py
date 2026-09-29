"""Generate golden cat-sprite fixtures from ClanGen for the Swift renderer port.

Run from the ClanGen repo root with its venv:

    cd /Users/dalton/Dev/temp/clangen
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        .venv/bin/python /Users/dalton/Dev/temp/kittyclan/tools/make_golden.py

Writes to KittyClanTests/Golden (relative to this script's repo):
  cat_NNN.png      raw 50x50 RGBA output of display_sprites.generate_sprite
  cats.json        appearance attributes for each cat
  collar_cells.json SHA-256 of every collar's recoloured cells, per collar id
  blend_cases.json pygame per-pixel blend results for each blend op used
"""

import hashlib
import json
import os
import random
import sys
from pathlib import Path
from types import SimpleNamespace

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
sys.path.insert(0, os.getcwd())

import pygame

pygame.init()
pygame.display.set_mode((1, 1))

import scripts.cat.sprites.load_sprites as load_sprites_mod

load_sprites_mod.is_today = lambda *_a, **_k: False
from scripts.cat.sprites.load_sprites import sprites

sprites.load_all()

from scripts.cat.enums import CatAge, CatGroup
from scripts.cat.pelts import Pelt
from scripts.cat.sprites import display_sprites
from scripts.game_structure import constants
from scripts.game_structure.game.settings import game_setting_get, game_setting_set

game_setting_set("shaders", False)
assert game_setting_get("shaders") is False
constants.CONFIG["fun"]["april_fools"] = False
constants.CONFIG["fun"]["all_cats_are_newborn"] = False

OUT = Path(__file__).resolve().parent.parent / "KittyClanTests" / "Golden"
SEED = 20260927
N_CATS = 60
AGES = list(CatAge)


def make_cat(pelt: Pelt, age: CatAge):
    return SimpleNamespace(
        pelt=pelt,
        age=age,
        dead=False,
        not_working=lambda: False,
        status=SimpleNamespace(group=CatGroup.PLAYER_CLAN),
        prevent_fading=True,
        faded=False,
    )


def eye_group(colour):
    for group in (Pelt.yellow_eyes, Pelt.green_eyes, Pelt.blue_eyes):
        if colour in group:
            return group
    raise ValueError(colour)


def force_pattern(p: Pelt, name: str):
    p.name = name
    if name in Pelt.torties:
        p.tortie_base = random.choice(
            Pelt.tabbies + Pelt.spotted + Pelt.plain + Pelt.exotic
        )
        p.tortie_marking = None
        if name == "Calico" or p.white_patches in (
            Pelt.high_white + Pelt.mostly_white + ["FULLWHITE"]
        ):
            p.randomize_white_patches()
    elif name == "TwoColour" and not p.white_patches:
        p.randomize_white_patches()
    elif name == "SingleColour":
        p.white_patches = None
        p.points = None


def build_cats():
    random.seed(SEED)
    cats = []
    for i in range(N_CATS):
        age = AGES[i % len(AGES)]
        gender = random.choice(("male", "female"))
        cats.append([Pelt.generate_new_pelt(gender, (), age), age])

    patterns = Pelt.pelt_patterns
    colours = Pelt.all_pelt_colours

    # every colour, then every pattern (so tortie colour fix-ups apply on top)
    for i, colour in enumerate(colours):
        cats[i][0].colour = colour
    forced_names = list(patterns) + ["Tortie"] * 5 + ["Calico"] * 3
    for i, name in enumerate(forced_names):
        force_pattern(cats[i][0], name)
    for p, _ in cats[: len(forced_names)]:
        p.init_pattern()
    # keep WHITE represented if a tortie fix-up replaced it
    if not any(p.colour == "WHITE" for p, _ in cats):
        p = cats[30][0]
        if p.name not in Pelt.torties:
            p.colour = "WHITE"

    # vitiligo x3
    for i in (26, 33, 40):
        cats[i][0].vitiligo = random.choice(Pelt.vitiligo_markings)

    # points x3 (non-tortie; keep white patches at little/mid so the point shows)
    for i, idx in enumerate((27, 34, 41)):
        p = cats[idx][0]
        if p.name == "Tortie":
            force_pattern(p, "Tabby")
            p.init_pattern()
        p.points = Pelt.point_markings[i % len(Pelt.point_markings)]
        if p.white_patches in (Pelt.high_white + Pelt.mostly_white + ["FULLWHITE"]):
            p.white_patches = random.choice(Pelt.little_white)

    # heterochromia x3
    for idx in (28, 35, 42):
        p = cats[idx][0]
        others = [
            g for g in (Pelt.yellow_eyes, Pelt.blue_eyes, Pelt.green_eyes)
            if g is not eye_group(p.eye_colour)
        ]
        p.eye_colour2 = random.choice(random.choice(others))

    # scars: general, general, missing-part NOTAIL + general, LEFTEAR alone
    cats[29][0].scars = (random.choice(Pelt.general_scars),)
    cats[36][0].scars = (random.choice(Pelt.general_scars),)
    cats[43][0].scars = ("NOTAIL", random.choice(Pelt.general_scars))
    cats[45][0].scars = ("LEFTEAR",)

    # accessories: plant head, plant tail/body, wild tail, wild body, plus a collar
    acc_idx = (30, 37, 44, 46, 47)
    picks = [
        random.choice([a for a in Pelt.plant_accessories if a in Pelt.body_accessories]),
        random.choice([a for a in Pelt.plant_accessories if a in Pelt.tail_accessories]),
        random.choice([a for a in Pelt.wild_accessories if a in Pelt.tail_accessories]),
        random.choice([a for a in Pelt.wild_accessories if a in Pelt.body_accessories]),
        random.choice(Pelt.collar_accessories),
    ]
    for idx, acc in zip(acc_idx, picks):
        cats[idx][0].accessory = (acc,)
    cats[48][0].accessory = (
        random.choice([a for a in Pelt.plant_accessories if a in Pelt.paw_accessories]),
        random.choice(Pelt.collar_accessories),
    )

    for p, age in cats:
        p.init_tint()

    # one of each tint table, regardless of what init_tint rolled
    cats[50][0].tint = "night"
    cats[51][0].tint = "pinkdilute"
    cats[52][0].tint = "densecocoa"
    return cats


def build_collar_cats():
    """Targeted collar fixtures, drawn after the main cats so their random rolls are unchanged.

    Colours ending in a digit stay on poses 10 and up, where Clangen's sprite keys don't collide.
    """
    wild_tail = [a for a in Pelt.wild_accessories if a in Pelt.tail_accessories]
    specs = [
        (CatAge.ADULT, ("LEATHER_BELL_SPIKE_white_gold2",)),
        (CatAge.SENIOR, ("NYLON_BELL_white1",)),
        (CatAge.ADULT, (random.choice([c for c in Pelt.collar_accessories if c.startswith("PUFFBALL_DOUBLECOLOR_")]),)),
        (CatAge.YOUNG_ADULT, (random.choice([c for c in Pelt.collar_accessories if c.startswith("BOW_FOIL_")]),)),
        (CatAge.SENIOR_ADULT, ("NYLON_black_gold",)),
        (CatAge.ADULT, (random.choice(wild_tail), random.choice(Pelt.collar_accessories))),
        (CatAge.KITTEN, ("PUFFBALL_GRADIENT_rainbow",)),
        (CatAge.ADOLESCENT, ("LEATHER_BELL_crimson",)),
    ]
    cats = []
    for age, accessories in specs:
        p = Pelt.generate_new_pelt(random.choice(("male", "female")), (), age)
        p.accessory = accessories
        p.init_tint()
        cats.append([p, age])
    return cats


def collar_cells():
    """SHA-256 of each collar's cells in pose order, recoloured like `apply_palettes` but
    from a fresh copy of each base cell, so Clangen's colliding sprite keys don't apply."""
    data = sprites.COLLAR_DATA
    sheet = pygame.image.load("sprites/acc_collars.png").convert_alpha()
    poses = sprites.POSE_DATA["poses"]
    out = {}
    for row, group in enumerate(data["style_data"]):
        for col, (style, colours) in enumerate(group.items()):
            palette = pygame.image.load(f"sprites/palettes/acc_collars{style}_palette.png")
            rows = pygame.PixelArray(palette)
            table = [[palette.unmap_rgb(px) for px in rows[::, y]] for y in range(rows.shape[1])]
            rows.close()
            for k, colour in enumerate(colours[: len(table) - 1], start=1):
                digest = hashlib.sha256()
                for i, pose in enumerate(poses):
                    if pose == "":
                        continue
                    x = col * 4 * 50 + (i % 4) * 50
                    y = row * 8 * 50 + (i // 4) * 50
                    cell = pygame.PixelArray(sheet.subsurface(x, y, 50, 50).copy())
                    for base, new in zip(table[0], table[k]):
                        cell.replace(base, new)
                    surf = cell.make_surface()
                    cell.close()
                    digest.update(pygame.image.tobytes(surf, "RGBA"))
                out[f"{style}_{colour}"] = digest.hexdigest()
    return out


def pose_index(p: Pelt, age: CatAge) -> int:
    return sprites.POSE_DATA["poses"].index(p.cat_sprites[age])


def pelt_json(i, p: Pelt, age):
    return {
        "id": f"cat_{i:03d}",
        "pose": pose_index(p, age),
        "name": p.name,
        "colour": p.colour,
        "length": p.length,
        "eyeColour": p.eye_colour,
        "eyeColour2": p.eye_colour2,
        "whitePatches": p.white_patches,
        "points": p.points,
        "vitiligo": p.vitiligo,
        "tortieBase": p.tortie_base,
        "tortiePattern": p.tortie_pattern,
        "tortieColour": p.tortie_colour,
        "tortieMarking": p.tortie_marking,
        "skin": p.skin,
        "scars": list(p.scars),
        "accessories": list(p.accessory or ()),
        "tint": p.tint,
        "whitePatchesTint": p.white_patches_tint,
        "reverse": bool(p.reverse),
    }


def render(p: Pelt, age) -> pygame.Surface:
    cat = make_cat(p, age)
    original = display_sprites.image_cache.load_image

    def fail(*_a, **_k):
        raise RuntimeError("generate_sprite fell back to the error placeholder")

    display_sprites.image_cache.load_image = fail
    try:
        surf = display_sprites.generate_sprite(cat, disable_sick_sprite=True)
    finally:
        display_sprites.image_cache.load_image = original
    assert surf.get_size() == (50, 50), surf.get_size()
    return surf


def blend_cases():
    """Per-pixel results from pygame for every blend op the renderer uses."""
    rng = random.Random(SEED + 1)
    n = 256
    edge = [0, 1, 127, 128, 254, 255]
    dst_px, src_px = [], []
    for k in range(n):
        if k < len(edge) ** 2:
            a, b = edge[k // len(edge)], edge[k % len(edge)]
            dst_px.append((rng.randrange(256), rng.randrange(256), rng.randrange(256), a))
            src_px.append((rng.randrange(256), rng.randrange(256), rng.randrange(256), b))
        else:
            dst_px.append(tuple(rng.randrange(256) for _ in range(4)))
            src_px.append(tuple(rng.randrange(256) for _ in range(4)))

    def surf(px):
        s = pygame.Surface((n, 1), pygame.SRCALPHA)
        for x, c in enumerate(px):
            s.set_at((x, 0), c)
        return s

    ops = {
        "normal": (0, 100),
        "normal_opacity_50": (0, 50),
        "normal_opacity_33": (0, 33),
        "rgba_mult": (pygame.BLEND_RGBA_MULT, 100),
        "rgb_mult": (pygame.BLEND_RGB_MULT, 100),
        "rgb_add": (pygame.BLEND_RGB_ADD, 100),
        "rgb_sub": (pygame.BLEND_RGB_SUB, 100),
        "rgba_min": (pygame.BLEND_RGBA_MIN, 100),
    }
    out = {"dst": [list(c) for c in dst_px], "src": [list(c) for c in src_px], "ops": {}}
    for name, (flag, opacity) in ops.items():
        d = surf(dst_px)
        display_sprites.blit_with_opacity(d, surf(src_px), opacity, special_flags=flag)
        out["ops"][name] = {
            "flag": flag,
            "opacity": opacity,
            "result": [list(d.get_at((x, 0))) for x in range(n)],
        }
    return out


def coverage(cats):
    ps = [p for p, _ in cats]
    tints = sprites.cat_tints
    return {
        "Tortie": sum(p.name == "Tortie" for p in ps),
        "Calico": sum(p.name == "Calico" for p in ps),
        "vitiligo": sum(bool(p.vitiligo) for p in ps),
        "points": sum(bool(p.points) for p in ps),
        "heterochromia": sum(bool(p.eye_colour2) for p in ps),
        "scars": sum(bool(p.scars) for p in ps),
        "missing_part_scars": sum(
            any(s in Pelt.missing_part_scars for s in p.scars) for p in ps
        ),
        "plant_or_wild_acc": sum(
            any(a in Pelt.plant_accessories + Pelt.wild_accessories for a in (p.accessory or ()))
            for p in ps
        ),
        "collar_acc": sum(
            any(a in Pelt.collar_accessories for a in (p.accessory or ())) for p in ps
        ),
        "white_patches": sum(bool(p.white_patches) for p in ps),
        "white_patches_tint": sum(bool(p.white_patches_tint) for p in ps),
        "tint_multiply": sum(p.tint in tints["tint_colours"] for p in ps),
        "tint_dilute_add": sum(p.tint in tints["dilute_tint_colours"] for p in ps),
        "tint_dense_sub": sum(p.tint in tints["remove_tone_tint_colours"] for p in ps),
        "reverse_true": sum(bool(p.reverse) for p in ps),
        "reverse_false": sum(not p.reverse for p in ps),
        "patterns_missing": sorted(set(Pelt.pelt_patterns) - {p.name for p in ps}),
        "colours_missing": sorted(set(Pelt.all_pelt_colours) - {p.colour for p in ps}),
        "ages": {str(a): sum(age == a for _, age in cats) for a in AGES},
        "lengths": {l: sum(p.length == l for p in ps) for l in Pelt.pelt_length},
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cats = build_cats()
    records = []
    for i, (p, age) in enumerate(cats):
        pygame.image.save(render(p, age), str(OUT / f"cat_{i:03d}.png"))
        records.append(pelt_json(i, p, age))
    for i, (p, age) in enumerate(build_collar_cats(), start=len(cats)):
        pygame.image.save(render(p, age), str(OUT / f"cat_{i:03d}.png"))
        records.append(pelt_json(i, p, age))
    (OUT / "collar_cells.json").write_text(json.dumps(collar_cells(), indent=0) + "\n")
    (OUT / "cats.json").write_text(json.dumps(records, indent=2) + "\n")
    (OUT / "blend_cases.json").write_text(json.dumps(blend_cases()) + "\n")

    cov = coverage(cats)
    print(json.dumps(cov, indent=2))
    required = {
        "Tortie": 6, "Calico": 4, "vitiligo": 3, "points": 3, "heterochromia": 3,
        "scars": 3, "missing_part_scars": 1, "plant_or_wild_acc": 4,
        "tint_multiply": 1, "tint_dilute_add": 1, "tint_dense_sub": 1,
        "reverse_true": 1, "reverse_false": 1,
    }
    failures = [k for k, v in required.items() if cov[k] < v]
    if cov["patterns_missing"] or cov["colours_missing"]:
        failures.append("patterns/colours")
    if failures:
        sys.exit(f"coverage not met: {failures}")
    print(f"wrote {len(records)} cats to {OUT}")


if __name__ == "__main__":
    main()
