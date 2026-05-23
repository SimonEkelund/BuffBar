# BuffBar

A lightweight raid-consumable tracker for **World of Warcraft Anniversary / TBC Classic 2.5.x**.

Drag any consumable from your bag onto the `+` slot to start tracking it. Each
slot shows the buff timer, your current bag count, and a configurable short
label under the icon. The slot stays bright while the buff is up and fades
when it's missing — at a glance you can see what needs reapplying.

Works for:
- **Self-buffs** — elixirs, flasks, food (auto-detects "Well Fed" / item buff)
- **Weapon enchants** — sharpening stones, oils (asks main hand or off hand)
- **Chest enchants** — Lesser/Greater Rune of Warding (tooltip-scanned)
- **Plain consumables** — healthstones, mana pots (count-only tracking)

## Install

1. Drop the `BuffBar` folder into
   `World of Warcraft\_anniversary_\Interface\AddOns\`.
2. Enable **BuffBar** in the AddOns list at character select.
3. Type `/bb` in chat to open settings.

## Commands

| Command | Description |
|---|---|
| `/bb` or `/buffbar` | Open the settings window |
| `/bb lock` / `/bb unlock` | Lock or unlock the bar |
| `/bb clear` | Remove every tracked item |

## Click bindings

| Mode | Action |
|---|---|
| Unlocked (edit) | Right-click slot → remove from bar |
| Unlocked (edit) | Left-drag slot → reorder; drag far outside → remove |
| Locked (play) | Right-click slot → use item |

## Features

- Per-profile configuration with **Import / Export** strings for sharing
- Horizontal or vertical orientation
- Adjustable icon size, transparency, font (incl. LibSharedMedia fonts)
- Optional "only show in dungeons and raids" mode
- Optional hide-when-buff-is-active for clean raid-prep displays
- Auto-detects the real buff name applied by each item (handles food's
  Well Fed / item-specific procs)

## Files

- `Core.lua` — state, events, profile management, helpers
- `Bar.lua` — bar frame, slot pool, click handling, layout
- `AddZone.lua` — drag-target `+` slot
- `Menu.lua` — settings window (Configuration / Profiles / Help tabs)
- `BuffBar.toc` — addon manifest
