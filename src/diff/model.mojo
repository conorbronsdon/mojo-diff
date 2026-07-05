"""Data model for mojo-diff: opcodes and matching blocks.

`OpCode` mirrors one 5-tuple from Python `difflib.SequenceMatcher.get_opcodes()`:
a tag plus the half-open `[a_start, a_end)` / `[b_start, b_end)` index ranges into
the two line sequences. Tag is one of "equal", "replace", "delete", "insert".
"""


@fieldwise_init
struct OpCode(Copyable, Movable, Writable, Equatable):
    """One edit opcode over two `List[String]` sequences.

    Half-open ranges: `a[a_start:a_end]` in the first sequence maps to
    `b[b_start:b_end]` in the second under `tag`.
    """

    var tag: String  # "equal" / "replace" / "delete" / "insert"
    var a_start: Int
    var a_end: Int
    var b_start: Int
    var b_end: Int

    def __eq__(self, other: Self) -> Bool:
        return (
            self.tag == other.tag
            and self.a_start == other.a_start
            and self.a_end == other.a_end
            and self.b_start == other.b_start
            and self.b_end == other.b_end
        )

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "OpCode(",
            self.tag,
            ", ",
            self.a_start,
            ", ",
            self.a_end,
            ", ",
            self.b_start,
            ", ",
            self.b_end,
            ")",
        )


@fieldwise_init
struct Match(Copyable, Movable, Writable):
    """A maximal matching run: `a[i:i+size] == b[j:j+size]`."""

    var i: Int
    var j: Int
    var size: Int

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Match(", self.i, ", ", self.j, ", ", self.size, ")")
