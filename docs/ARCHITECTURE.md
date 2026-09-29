# KittyClan architecture

KittyClan ports ClanGen's simulation to Swift. The guiding rule is **fidelity**: when ClanGen has a number, a formula or a rule, KittyClan uses the same one, and ClanGen's own text is used for everything the player reads. Where ClanGen has an obvious bug, KittyClan fixes it, and the commit message records the difference.

## Layout

| Folder | Contents |
|---|---|
| `KittyClan/Model` | Plain `Codable` value types: `Clan`, `Cat`, `Relationship`, conditions, supplies, other Clans, afterlife records, family relations. No game logic beyond small helpers. |
| `KittyClan/Engine` | The simulation. `MoonEngine` advances a `Clan` by one moon, with extensions grouped by system (see below). `GameAssets` loads everything once at launch. |
| `KittyClan/Rendering` | `CatRenderer` composites cat sprites from ClanGen's sheets with integer blend math that matches pygame, so sprites are pixel-identical. |
| `KittyClan/App` | `AppModel` (the observable app state), founding flow state, save slots, sprite cache, audio, and debug launch arguments. |
| `KittyClan/Views` | SwiftUI screens, grouped by area: Camp, Clan, Detail, Controls, Founding, Afterlife, Patrol, LeaderDen, WarriorsDen, Mediation, Settings, Chooser. |
| `KittyClan/Resources` | Content exported from ClanGen (see "Content pipeline"). |
| `KittyClanTests` | XCTest suites per system, plus golden sprite renders from ClanGen in `Golden/`. |
| `tools/export_assets.py` | Converts a ClanGen checkout into `KittyClan/Resources`. |

## The moon

`MoonEngine.advance(_:using:)` follows the order of ClanGen's `events.one_moon`. Each moon it:
1. Ages the afterlife and handles fading.
2. Resolves wars, the leader's den, returning lost cats and pending future events such as murder reveals.
3. Feeds the Clan and brings in the moon's catch.
4. Runs every living Clan cat through aging, hunger, conditions, ceremonies, skills, pregnancy, relationships, new arrivals, misc and accessory events, death and illness rolls, and murder.
5. Handles outsiders.
6. Applies the Clan focus.
7. Runs the herb moon, then mentors and deputy selection.
8. Holds the mourning.
9. Assigns every cat a new thought.
10. Narrates the moon's events into the Clan's history.

Engine systems live in `Engine/<System>/MoonEngine+<System>.swift`:

| System | What it covers |
|---|---|
| Afterlife | StarClan, the Dark Forest and the Unknown Residence, the guide, fading, nine-lives ceremonies, grief and mourning, murder and its reveals |
| Conditions | Illnesses, injuries, permanent conditions, outbreaks, scars and herb treatment |
| Relationships | Interactions, mates and breakups, compatibility and mediation |
| Patrols | Patrol selection, outcomes, prey and the cats patrols create |
| Supplies | Fresh-kill pile, nutrition and herb stores |
| OtherClans | Neighbouring Clans, war, the leader's den, outsiders and other-Clan cats |
| Pregnancy | Pregnancy, births, adoption, and the pregnant and recovering-from-birth conditions |
| Focus | The warriors' den Clan focus |
| Disasters | Mass-death events (off by default) |
| Controls | Player actions: roles, mentors, mates, renaming |
| Thoughts | ClanGen's thought pools |
| Camp | Camp layouts and cat placement |
| Presentation / Audio | Clan symbols, profile backgrounds and playlists |

Randomness always comes from an explicit `inout some RandomNumberGenerator`, so tests use a seeded generator. Tests check invariants, text resolution and statistics rather than exact outcomes, because dictionary ordering varies between runs.

## Text

ClanGen's text is data, not code, and KittyClan reads the same files.
- **`EventLibrary`** loads ceremonies and short events (death, misc, injury, new cat, accessory, murder, mass death). It drops, at load time, any event that needs something KittyClan can't evaluate. That keeps the pools honest, and tests count what loads.
- **`Constraint`** evaluates ClanGen's involved-cat filters: status, age, trait, skill, backstory, group, past status, experience, relationships and tags. `Constraint.locationAllows` applies biome and camp rules.
- **`TextTemplate`** resolves `{PRONOUN}`, `{VERB}` and `{ADJ}` tags, cat abbreviations (`m_c`, `r_c`, `mur_c`, `n_c:0`…), Clan names, snippet lists and places.
- **`ClangenNarrator`** turns `MoonEvent`s into log entries.
- **`ThoughtLibrary`** picks each cat's thought.

Text that names cats is stored as a template plus cat IDs and resolved when shown, so names and pronouns stay current. This applies to death history, nine-lives ceremonies and thoughts.

## Rendering

`SpriteAtlas` slices 50×50 cells from sheets stored as raw, deflate-compressed RGBA (`.rgba`). iOS premultiplies PNG alpha, which would break ClanGen's blend math. `CatRenderer` follows ClanGen's `generate_sprite`:
1. Pelt recipes, tints, white patches, points and vitiligo.
2. Eyes and scars.
3. Lineart and skin.
4. Missing parts, then accessories, with collars recoloured from their palettes.
5. For dead cats, afterlife lineart, fading fog and overlays.

`RenderingTests` compares renders with golden images produced by ClanGen itself.

## Content pipeline

`tools/export_assets.py` reads a ClanGen checkout and writes:
- `Resources/Sprites`: sprite sheets as `.rgba`, `index.json` (flattened sprite tables, because Swift's JSON decoding doesn't keep key order), pelt recipes and names.
- `Resources/Text`: event, patrol, thought, condition, herb, snippet, place and pronoun JSON. English files are unwrapped from `{"en": …}`.
- `Resources/Camps`: camp backgrounds for each biome and season, plus layouts.
- `Resources/PatrolArt`, `Resources/Afterlife` and `Resources/Presentation`: art the game references.
- `Resources/Audio`: playlists only (see the README).

The exported files are committed, so building the app doesn't need ClanGen.

## Saves

- Each Clan is saved as JSON in Application Support under `Clans/<id>.json`, with a small `<id>.summary.json` for the Clan chooser (`SaveSlots`).
- Every `Cat` and `Clan` field added after the first release is decoded with `decodeIfPresent` and a default, so older saves keep loading. New fields must follow the same pattern.

## Conventions

- Model types are value types. The engine takes `inout Clan`, and the UI changes the Clan only through `AppModel` methods, which save afterwards.
- Engine code uses ClanGen's names in doc comments (e.g. "Clangen's `get_balanced_kit_chance`") so behaviour can be traced back to the original.
- Debug launch arguments (`-autofound`, `-timeskips`, `-showCat`, `-sheet`, …) put the app into a specific state for screenshots and manual testing. They exist only in Debug builds.
