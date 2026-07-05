#!/usr/bin/env python3
"""Generate diff fixtures + expected outputs from Python's difflib.

For each named case we write:
  <name>.a.txt          before text
  <name>.b.txt          after text
  <name>.unified.txt    difflib.unified_diff(a, b, "a", "b", n=3) joined

Line splitting matches mojo-diff's splitlines_keepends (split on "\n" only,
keep the terminator), so byte-for-byte comparison is meaningful.
"""
import difflib
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def keepends(text):
    # Split on "\n" only, keeping the terminator — matches the Mojo side.
    lines = []
    start = 0
    for i, ch in enumerate(text):
        if ch == "\n":
            lines.append(text[start:i + 1])
            start = i + 1
    if start < len(text):
        lines.append(text[start:])
    return lines


CASES = {}

# 1. code file edit: a function gains a guard clause and a renamed var.
CASES["code_edit"] = (
    "def load(path):\n"
    "    data = open(path).read()\n"
    "    rows = data.split(chr(10))\n"
    "    total = 0\n"
    "    for r in rows:\n"
    "        total += len(r)\n"
    "    return total\n",
    "def load(path):\n"
    "    if not path:\n"
    "        return 0\n"
    "    data = open(path).read()\n"
    "    lines = data.split(chr(10))\n"
    "    total = 0\n"
    "    for line in lines:\n"
    "        total += len(line)\n"
    "    return total\n",
)

# 2. prose edit: middle paragraph reworded, rest identical.
CASES["prose_edit"] = (
    "The quick brown fox.\n"
    "It jumped over the lazy dog.\n"
    "Then it ran into the woods.\n"
    "The end was near.\n"
    "Nothing more happened.\n",
    "The quick brown fox.\n"
    "It leapt over the sleeping dog.\n"
    "Then it ran into the woods.\n"
    "The end was near.\n"
    "Nothing more happened.\n",
)

# 3. empty -> content
CASES["empty_to_content"] = (
    "",
    "first line\nsecond line\nthird line\n",
)

# 4. identical
CASES["identical"] = (
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n",
)

# 5. total rewrite (no shared lines)
CASES["total_rewrite"] = (
    "one\ntwo\nthree\nfour\n",
    "apple\nbanana\ncherry\ndate\n",
)

# 6. trailing newline present on a, absent on b (last line)
CASES["no_newline_b"] = (
    "line one\nline two\nline three\n",
    "line one\nline two\nline three CHANGED",
)

# 7. trailing newline absent on both, single edit
CASES["no_newline_both"] = (
    "keep\nremove me\nkeep too",
    "keep\nkeep too",
)

# 8. content -> empty (full deletion)
CASES["content_to_empty"] = (
    "gone one\ngone two\ngone three\n",
    "",
)

# 9. multi-hunk: two separated edits in a long file (exercises grouping)
_base = ["ctx%02d\n" % i for i in range(30)]
_a = list(_base)
_b = list(_base)
_b[3] = "CHANGED-3\n"
_b[25] = "CHANGED-25\n"
CASES["multi_hunk"] = ("".join(_a), "".join(_b))

# 10. one-line files
CASES["one_line"] = ("only line\n", "only line changed\n")


def main():
    manifest = []
    for name, (a, b) in CASES.items():
        with open(os.path.join(HERE, name + ".a.txt"), "w", newline="") as f:
            f.write(a)
        with open(os.path.join(HERE, name + ".b.txt"), "w", newline="") as f:
            f.write(b)
        diff = "".join(
            difflib.unified_diff(keepends(a), keepends(b), "a", "b", n=3)
        )
        with open(
            os.path.join(HERE, name + ".unified.txt"), "w", newline=""
        ) as f:
            f.write(diff)
        # ratio over line lists (no keepends, matches how tests build lists)
        al = a.split("\n")
        bl = b.split("\n")
        r = difflib.SequenceMatcher(None, al, bl).ratio()
        manifest.append("%s ratio=%.10f" % (name, r))
    with open(os.path.join(HERE, "ratios.txt"), "w", newline="") as f:
        f.write("\n".join(manifest) + "\n")
    print("wrote fixtures for:", ", ".join(CASES.keys()))
    print("\n".join(manifest))


if __name__ == "__main__":
    main()
