# BuffBar — Open items

Tracked from guildie feedback. Ticked items are confirmed fixed in-game.

## Bugs

- [ ] **B1.** Creating a new profile deletes an existing one.
- [x] **B2.** "Already tracking" confusion with Greater Rune of Warding. *(Root cause: an imported profile already had the rune; on a client that never owned it GetItemInfo returns nil so the slot showed a faint "?" at 0 count and was easy to miss → re-drag → "already tracking". Fix: clearer message naming the item + flash the existing slot so it's obvious where it already lives. Confirmed 0-count/uncached items still render and resolve via GET_ITEM_INFO_RECEIVED.)*
- [~] **B3.** Food / eating-buff slot stays bright while Well Fed is active. *(Fixed pending in-game confirm: combat-guarded layout so the bar can't collapse on UNIT_AURA; eating buffs blacklisted so the slot binds to "Well Fed", not the transient "Food".)*

## Features

- [ ] **F1.** Active profile should be per-character; the profile *library* stays account-wide.
- [x] **F4.** Charges on oil-type items. *(Decision: keep showing bottle/item count only — charges display not wanted. No code change; charges scaffolding reverted.)*
- [ ] **F2.** Alignment option (Left / Center, default Left). Centered bar should stay centered when icons hide / get removed so existing slots don't shift and cause misclicks.
- [x] **F3.** "Eating in progress" placeholder timer on a food slot while the cast is still running and Well Fed hasn't landed. *(Done: reads the required sit time straight from the food tooltip ("spend at least N seconds eating"), counts down to Well Fed from the exact eat-start, click-independent, shown even when "show duration" is off.)*

- [x] **F2.** Center alignment option. *(Done: "Keep icons centered" checkbox — pins the row centre so icons stay centred and the row shrinks symmetrically as buffs hide; lock/unlock doesn't shift icons. Works horizontal + vertical.)*
- [~] **F5.** Quick-open settings while locked. *(Done pending in-game confirm: middle-click any icon opens the settings menu in any lock state. Chosen over shift-right-click to avoid clashing with the secure right-click consume. Documented in AddZone/grip tooltips and the Help tab.)*

## Working order (most painful → polish)

1. B1 — profile deletion (data loss)
2. B2 — adding rune blocked
3. F1 — per-char profile (raid-team use case)
4. F4 — oil charges
5. B3 — food buff regression
6. F2 — alignment option
7. F3 — eating placeholder
8. F5 — quick-open settings
