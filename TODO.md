# BuffBar — Open items

Tracked from guildie feedback. Ticked items are confirmed fixed in-game.

## Bugs

- [ ] **B1.** Creating a new profile deletes an existing one.
- [ ] **B2.** "Already tracking" false positive when dragging Greater Rune of Warding (item is not in the list).
- [ ] **B3.** Food / eating-buff slot stays bright while Well Fed is active.

## Features

- [ ] **F1.** Active profile should be per-character; the profile *library* stays account-wide.
- [ ] **F4.** Show charges remaining (e.g. 5/5) on oil-type items instead of item count.
- [ ] **F2.** Alignment option (Left / Center, default Left). Centered bar should stay centered when icons hide / get removed so existing slots don't shift and cause misclicks.
- [ ] **F3.** "Eating in progress" placeholder timer (~10 s) on a food slot while the cast is still running and the Well Fed buff hasn't landed yet.
- [ ] **F5.** Quick-open settings while locked. Bind a gesture (right-click grip area / shift-right-click slot / middle-click) that opens `/bb` without typing.

## Working order (most painful → polish)

1. B1 — profile deletion (data loss)
2. B2 — adding rune blocked
3. F1 — per-char profile (raid-team use case)
4. F4 — oil charges
5. B3 — food buff regression
6. F2 — alignment option
7. F3 — eating placeholder
8. F5 — quick-open settings
