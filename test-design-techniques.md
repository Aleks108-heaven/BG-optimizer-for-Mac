# Test Design Techniques (ISTQB-aligned)

- **Equivalence partitioning**: split inputs into valid/invalid classes; test one value per class.
- **Boundary value analysis**: test min-1, min, min+1, max-1, max, max+1 for every range (length, quantity, dates, file size).
- **Decision tables**: enumerate condition combinations (roles x states x flags) and expected actions.
- **State transition**: model states/events (order: created, paid, shipped, refunded); test valid and invalid transitions.
- **Pairwise/combinatorial**: cover all parameter pairs for browser x OS x locale x role matrices.
- **Use-case/scenario**: end-to-end user journeys including alternate and exception flows.
- **Error guessing**: past defects, null/empty, leap days, DST, negative numbers, emoji, RTL text, double-submit, race conditions.
- **Exploratory (session-based)**: charter + time-box + notes + debrief.
- **Experience heuristics**: SFDIPOT, CRUD, FEW HICCUPPS, "goldilocks" (too big/small/just right).
