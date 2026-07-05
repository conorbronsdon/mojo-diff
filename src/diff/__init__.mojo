"""mojo-diff: pure-Mojo line diffing mirroring Python's `difflib` API."""

from diff.model import OpCode, Match
from diff.diff import (
    splitlines_keepends,
    matching_blocks,
    get_opcodes,
    ratio,
    unified_diff,
)
