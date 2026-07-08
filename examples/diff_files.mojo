"""Print a unified diff of two files. Usage: diff_files <a> <b> [context]."""

from std.sys import argv

from diff import unified_diff


def main() raises:
    var args = argv()
    if len(args) < 3:
        print("usage: diff_files <a> <b> [context]")
        return
    var context = 3
    if len(args) >= 4:
        context = Int(String(args[3]))
    var a = open(String(args[1]), "r").read()
    var b = open(String(args[2]), "r").read()
    print(unified_diff(a, b, String(args[1]), String(args[2]), context), end="")
