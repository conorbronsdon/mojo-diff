"""Throughput benchmark for `unified_diff` over the repo's own test fixtures.

Reports wall-clock per diff. The fixture pairs are tiny (roughly 100-300
bytes each), so every pair is diffed many thousands of times to get stable
numbers; treat results as relative between fixtures/commits, not as absolute
throughput on real-world inputs. Run compiled for meaningful numbers:
`mojo build -I src bench/bench_diff.mojo -o .bench_diff && ./.bench_diff`
(or `pixi run bench`).
"""
from std.time import perf_counter_ns

from diff import unified_diff


def bench(name: String, iterations: Int) raises:
    var a = open("test/data/" + name + ".a.txt", "r").read()
    var b = open("test/data/" + name + ".b.txt", "r").read()
    var total_bytes = a.byte_length() + b.byte_length()
    # Warmup + correctness anchor: require a stable output size.
    var warm = unified_diff(a, b)
    var out_len = warm.byte_length()
    var start = perf_counter_ns()
    for _ in range(iterations):
        var out = unified_diff(a, b)
        if out.byte_length() != out_len:
            raise Error("inconsistent diff output")
    var elapsed_ns = perf_counter_ns() - start
    var per_diff_us = Float64(elapsed_ns) / Float64(iterations) / 1e3
    print(t"{name}: {total_bytes} input bytes, {out_len} diff bytes")
    print(t"  {per_diff_us} us/diff over {iterations} iterations")


def main() raises:
    bench("code_edit", 20000)
    bench("prose_edit", 20000)
    bench("multi_hunk", 20000)
    bench("total_rewrite", 20000)
