# Security Policy

mojo-diff is a pure-Mojo text-diffing library with no network access, no
authentication, and no secrets handling: it takes two sequences of lines
and returns opcodes or unified-diff text. The main risk surface is
malformed or adversarial input (extremely long lines, pathological
repeated-line patterns) causing a crash, hang, or unbounded memory
growth, which the fuzz suite (`test/fuzz_runner.mojo`) specifically
targets.

If you find an input that crashes, hangs, or otherwise misbehaves in a
way that looks security-relevant, please report it via a
[GitHub issue](https://github.com/conorbronsdon/mojo-diff/issues),
including the two inputs that trigger it.

This is a personal open-source project maintained on a best-effort
basis. There's no formal SLA for response time, but reports are welcome
and taken seriously.
