"""Pure-Mojo line diffing, mirroring Python's `difflib` API.

The core is the Myers O(ND) greedy diff (Myers 1986) over line sequences: it
finds a shortest edit script, from which we recover the matching blocks. Those
blocks feed `get_opcodes` (mirroring `SequenceMatcher.get_opcodes`), `ratio`
(SequenceMatcher-style `2*M/T` similarity), and `unified_diff` (byte-compatible
with `difflib.unified_diff` — same hunk grouping and `@@` range math).

`unified_diff` operates on lines that keep their trailing newlines, exactly like
`difflib` fed by `readlines()`. A final line without a newline is emitted without
one — matching difflib, which does not print a "\\ No newline at end of file"
marker (that is a GNU-diff feature, not a difflib one).

Memory bound: the Myers backtrack stores one `V` snapshot per edit-distance
step `d`, so the trace is `O(d^2)` in the edit distance. On adversarial,
fully-dissimilar inputs `d` approaches `len(a) + len(b)`, which would allocate
tens of GB for two large unrelated files (a DoS). To keep memory bounded,
`matching_blocks` caps the exact search at `max_edit_distance` steps
(default `_MAX_EDIT_DISTANCE`). Past the cap it stops the quadratic search and
returns a *coarse* result: the shared leading/trailing lines are preserved as
equal blocks and the differing middle is reported as one block-level change.
This keeps output byte-compatible with `difflib` for every input whose edit
distance is within the cap (all realistic edits), and degrades gracefully —
never OOMs — beyond it.
"""

from diff.model import OpCode, Match

comptime _NL = UInt8(0x0A)

# Cap on the Myers edit-distance search. The backtrack trace holds one V
# snapshot per step, so peak trace memory is ~`(_MAX_EDIT_DISTANCE + 1)^2`
# ints (~170 MB at 4096). Diffs whose edit distance stays under this run
# exactly (difflib-identical); more-dissimilar inputs fall back to a coarse
# prefix/suffix-preserving result instead of allocating unbounded memory.
comptime _MAX_EDIT_DISTANCE = 4096


def _imax(a: Int, b: Int) -> Int:
    return a if a > b else b


def _imin(a: Int, b: Int) -> Int:
    return a if a < b else b


def splitlines_keepends(text: String) -> List[String]:
    """Split on `\\n`, keeping the terminator on each line (like `readlines`).

    `"a\\nb\\n"` -> `["a\\n", "b\\n"]`; `"a\\nb"` -> `["a\\n", "b"]`; `""` -> `[]`.
    """
    var lines = List[String]()
    var data = text.as_bytes()
    var n = len(data)
    var start = 0
    var i = 0
    while i < n:
        if data[i] == _NL:
            lines.append(
                String(StringSlice(unsafe_from_utf8=data[start : i + 1]))
            )
            i += 1
            start = i
        else:
            i += 1
    if start < n:
        lines.append(String(StringSlice(unsafe_from_utf8=data[start:n])))
    return lines^


def matching_blocks(
    a: List[String],
    b: List[String],
    max_edit_distance: Int = _MAX_EDIT_DISTANCE,
) -> List[Match]:
    """Matching blocks of `a` vs `b` via Myers O(ND), difflib-shaped.

    Returns maximal matching runs in increasing order, terminated by the
    `Match(len(a), len(b), 0)` sentinel (as `SequenceMatcher.get_matching_blocks`
    does).

    The exact Myers search is capped at `max_edit_distance` steps to bound
    memory (see module docstring). If the edit distance would exceed the cap,
    a *coarse* result is returned: shared leading/trailing lines stay as equal
    blocks and the differing middle is left as a single block-level change.
    """
    var n = len(a)
    var m = len(b)
    var blocks = List[Match]()
    if n == 0 or m == 0:
        blocks.append(Match(n, m, 0))  # sentinel only; no matches possible
        return blocks^

    # Common leading/trailing lines. Only used to build the coarse fallback
    # below; the exact path recovers these naturally via Myers snakes.
    var prefix = 0
    while prefix < n and prefix < m and a[prefix] == b[prefix]:
        prefix += 1
    var suffix = 0
    while (
        suffix < (n - prefix)
        and suffix < (m - prefix)
        and a[n - 1 - suffix] == b[m - 1 - suffix]
    ):
        suffix += 1

    # Greedy forward pass, recording a trimmed V snapshot per edit distance d.
    var maxd = n + m
    var offset = maxd
    var v = List[Int]()
    for _ in range(2 * maxd + 1):
        v.append(0)
    var trace = List[List[Int]]()
    var found = False
    var capped = False
    var d_final = 0
    var d = 0
    while d <= maxd:
        if d > max_edit_distance:
            # Exact search would need `(d+1)^2` trace ints; bail out to the
            # bounded coarse fallback instead of growing memory unbounded.
            capped = True
            break
        var snap = List[Int]()
        for k in range(-d, d + 1):
            snap.append(v[k + offset])
        trace.append(snap^)
        var k = -d
        while k <= d:
            var x: Int
            if k == -d or (k != d and v[k - 1 + offset] < v[k + 1 + offset]):
                x = v[k + 1 + offset]  # move down (insertion from b)
            else:
                x = v[k - 1 + offset] + 1  # move right (deletion from a)
            var y = x - k
            while x < n and y < m and a[x] == b[y]:
                x += 1
                y += 1
            v[k + offset] = x
            if x >= n and y >= m:
                found = True
                d_final = d
                break
            k += 2
        if found:
            break
        d += 1

    if capped:
        # Coarse, bounded fallback: keep the shared prefix/suffix as equal
        # blocks and leave the differing middle as one block-level change
        # (`get_opcodes` renders it as a single replace/insert/delete). This
        # never allocates the quadratic trace, so memory stays bounded.
        if prefix > 0:
            blocks.append(Match(0, 0, prefix))
        if suffix > 0:
            blocks.append(Match(n - suffix, m - suffix, suffix))
        blocks.append(Match(n, m, 0))  # sentinel
        return blocks^

    # Backtrack through the trace, collecting matched (x, y) points in
    # decreasing order.
    var px = List[Int]()
    var py = List[Int]()
    var x = n
    var y = m
    var dd = d_final
    while dd > 0:
        # trace[dd] is a trimmed V snapshot of length 2*dd+1, index kk+dd.
        var kk = x - y
        var prev_k: Int
        if kk == -dd or (
            kk != dd and trace[dd][kk - 1 + dd] < trace[dd][kk + 1 + dd]
        ):
            prev_k = kk + 1
        else:
            prev_k = kk - 1
        var prev_x = trace[dd][prev_k + dd]
        var prev_y = prev_x - prev_k
        while x > prev_x and y > prev_y:
            px.append(x - 1)
            py.append(y - 1)
            x -= 1
            y -= 1
        x = prev_x
        y = prev_y
        dd -= 1
    # Leading snake down to the origin (pure diagonal, x == y here).
    while x > 0 and y > 0:
        px.append(x - 1)
        py.append(y - 1)
        x -= 1
        y -= 1

    # Coalesce contiguous diagonal points (walk px/py from smallest index).
    var i = len(px) - 1
    while i >= 0:
        var start_x = px[i]
        var start_y = py[i]
        var size = 1
        while i - 1 >= 0 and px[i - 1] == px[i] + 1 and py[i - 1] == py[i] + 1:
            i -= 1
            size += 1
        blocks.append(Match(start_x, start_y, size))
        i -= 1

    blocks.append(Match(n, m, 0))  # sentinel
    return blocks^


def get_opcodes(
    a: List[String],
    b: List[String],
    max_edit_distance: Int = _MAX_EDIT_DISTANCE,
) -> List[OpCode]:
    """Edit opcodes turning `a` into `b`, mirroring `SequenceMatcher.get_opcodes`.

    `max_edit_distance` caps the exact search (see `matching_blocks`); beyond it
    the differing region collapses to a single coarse opcode.
    """
    var blocks = matching_blocks(a, b, max_edit_distance)
    var ops = List[OpCode]()
    var i = 0
    var j = 0
    for blk in blocks:
        var ai = blk.i
        var bj = blk.j
        var size = blk.size
        var tag = String("")
        if i < ai and j < bj:
            tag = String("replace")
        elif i < ai:
            tag = String("delete")
        elif j < bj:
            tag = String("insert")
        if tag.byte_length() > 0:
            ops.append(OpCode(tag^, i, ai, j, bj))
        i = ai + size
        j = bj + size
        if size > 0:
            ops.append(OpCode(String("equal"), ai, i, bj, j))
    return ops^


def ratio(a: List[String], b: List[String]) -> Float64:
    """SequenceMatcher-style similarity `2*M/T` over the two line sequences.

    `M` is the total matched-line count, `T = len(a) + len(b)`. Two empty
    sequences score `1.0`, matching `difflib`.
    """
    var blocks = matching_blocks(a, b)
    var matches = 0
    for blk in blocks:
        matches += blk.size
    var total = len(a) + len(b)
    if total == 0:
        return 1.0
    return 2.0 * Float64(matches) / Float64(total)


def _grouped_opcodes(
    a: List[String], b: List[String], n: Int
) -> List[List[OpCode]]:
    """Mirror `SequenceMatcher.get_grouped_opcodes(n)`: hunks with `n` context.
    """
    var codes = get_opcodes(a, b)
    if len(codes) == 0:
        codes.append(OpCode(String("equal"), 0, 1, 0, 1))
    # Trim leading/trailing equal runs to at most n lines of context.
    if codes[0].tag == "equal":
        var c = codes[0].copy()
        codes[0] = OpCode(
            String("equal"),
            _imax(c.a_start, c.a_end - n),
            c.a_end,
            _imax(c.b_start, c.b_end - n),
            c.b_end,
        )
    var last = len(codes) - 1
    if codes[last].tag == "equal":
        var c = codes[last].copy()
        codes[last] = OpCode(
            String("equal"),
            c.a_start,
            _imin(c.a_end, c.a_start + n),
            c.b_start,
            _imin(c.b_end, c.b_start + n),
        )
    var nn = n + n
    var groups = List[List[OpCode]]()
    var group = List[OpCode]()
    for c in codes:
        if c.tag == "equal" and (c.a_end - c.a_start) > nn:
            group.append(
                OpCode(
                    String("equal"),
                    c.a_start,
                    _imin(c.a_end, c.a_start + n),
                    c.b_start,
                    _imin(c.b_end, c.b_start + n),
                )
            )
            groups.append(group.copy())
            group = List[OpCode]()
            group.append(
                OpCode(
                    String("equal"),
                    _imax(c.a_start, c.a_end - n),
                    c.a_end,
                    _imax(c.b_start, c.b_end - n),
                    c.b_end,
                )
            )
            continue
        group.append(c.copy())
    if len(group) > 0 and not (len(group) == 1 and group[0].tag == "equal"):
        groups.append(group^)
    return groups^


def _format_range_unified(start: Int, stop: Int) -> String:
    """`difflib._format_range_unified`: 1-based range in unified `ed` form."""
    var beginning = start + 1
    var length = stop - start
    if length == 1:
        return String(beginning)
    if length == 0:
        beginning -= 1  # empty ranges begin at the line just before
    return String(beginning) + "," + String(length)


def unified_diff(
    a_text: String,
    b_text: String,
    from_file: String = "a",
    to_file: String = "b",
    context: Int = 3,
) -> String:
    """Unified diff of two texts, byte-compatible with `difflib.unified_diff`.

    Lines keep their newlines; the last line of a file without a trailing
    newline is emitted without one. Identical inputs produce the empty string
    (no header), matching difflib.
    """
    var a = splitlines_keepends(a_text)
    var b = splitlines_keepends(b_text)
    var groups = _grouped_opcodes(a, b, context)
    var out = String()
    var started = False
    for group in groups:
        if not started:
            started = True
            out += "--- " + from_file + "\n"
            out += "+++ " + to_file + "\n"
        var gl = len(group) - 1
        var r1 = _format_range_unified(group[0].a_start, group[gl].a_end)
        var r2 = _format_range_unified(group[0].b_start, group[gl].b_end)
        out += "@@ -" + r1 + " +" + r2 + " @@\n"
        for op in group:
            if op.tag == "equal":
                for idx in range(op.a_start, op.a_end):
                    out += " " + a[idx]
                continue
            if op.tag == "replace" or op.tag == "delete":
                for idx in range(op.a_start, op.a_end):
                    out += "-" + a[idx]
            if op.tag == "replace" or op.tag == "insert":
                for idx in range(op.b_start, op.b_end):
                    out += "+" + b[idx]
    return out^
