# Changelog

## Unreleased

### Added
- Tutorial: a guided seven-step match, reachable from the main menu.
- Gamepad support: virtual cursor, command grid on the trigger and D-pad,
  control groups, menu navigation, rebinding, Xbox / PlayStation / Steam Deck
  button names, Steam Deck defaults and 1280 x 800.
- French, Italian, German and Spanish text and subtitles (machine drafts
  awaiting native review), with a Language setting.

### Fixed
- Saves are verified before they replace the previous file, and the previous
  file is kept as a backup. A damaged save falls back to its backup; a damaged
  slot is shown as unreadable and asks before it is overwritten.
- Campaign progress is written atomically. A damaged progress file is set aside
  as `campaign.save.damaged` and reported, not silently reset.
- A failed load no longer discards the match in progress, and loading an older
  save no longer re-locks missions.
- Gather objectives count resources delivered by Workers. Salvage Rights no
  longer completes its first objective on the starting stock.
- First Signal: the survival objective starts when the counterattack arrives.
- Ghost Protocol: the rewrite wave cannot arrive before four minutes.
- The opponent no longer stalls when it has no Generator and no energy.
- Rebinding can no longer take a command-grid key away from its slot.
- Borderless window mode covers the whole screen.

### Changed
- Development switches (`--demo`, `--benchmark`, `--autoplay`, `--focus` and
  the capture options) are ignored by release builds.
- The match pauses when the window loses focus (Settings → Pause in background).
- Key labels follow the player's keyboard layout.
- The main menu shows the version.
- Autosaves continue their rotation across launches.
- Builds carry the font and asset licences in `licenses/` and no longer ship
  developer documents or unused source models.

## 1.0.0-rc3

Skirmish on all eight maps, three difficulty levels, alerts, hold/patrol/stance
orders, unit abilities, terrain effects, faction units, save slots.

## 1.0.0-rc2

Dock HUD, technology tree, sprite atlases, world look pass.

## 1.0.0-rc1

First release candidate: eight-mission campaign, tests and CI.
