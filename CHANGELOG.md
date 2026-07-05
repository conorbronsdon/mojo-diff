# Changelog

## 0.1.0 — 2026-07-05

Initial release. Pure-Mojo line diffing mirroring Python's `difflib` API:
the Myers O(ND) greedy diff algorithm behind `get_opcodes`,
`matching_blocks`, `ratio`, and `unified_diff`. `unified_diff` matches
`difflib.unified_diff` byte-for-byte on the fixture corpus (hunk grouping,
`@@` range math, and no-trailing-newline handling). 32 tests, including
11/11 unified-diff fixtures matching difflib exactly and a performance
test (5,000 lines in roughly 0.9ms).
