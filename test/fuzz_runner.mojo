"""Fuzz target: diff argv[1] against a shuffled copy of itself.

Prints the opcode count; a raise is reported, not fatal (crashing/hanging is the
only real failure). Run: `mojo run -I src test/fuzz_runner.mojo <file>`.
"""

from std.sys import argv
from std.random import random_ui64, seed

from diff import get_opcodes, splitlines_keepends


def main():
    try:
        var text = open(String(argv()[1]), "r").read()
        var a = splitlines_keepends(text)
        var b = a.copy()
        seed()
        # Fisher-Yates shuffle of the copy.
        var i = len(b) - 1
        while i > 0:
            var j = Int(random_ui64(0, UInt64(i)))
            var tmp = b[i].copy()
            b[i] = b[j].copy()
            b[j] = tmp^
            i -= 1
        var ops = get_opcodes(a, b)
        print("lines:", len(a), "opcodes:", len(ops))
    except e:
        print("raised:", e)
