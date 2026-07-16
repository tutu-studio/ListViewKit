# ListViewKit Runtime Benchmarks

The benchmark uses deterministic fixed-height data sets containing 1,000,
10,000, and 100,000 rows. It measures:

- Initial snapshot application and layout-cache construction.
- 20,000 visible-range queries across the full content height.
- 1,000 scrolling layout passes, including row recycling and reuse.
- 1,000 direct item updates and targeted height invalidations of the final row,
  modeling a growing streaming response without diffing a complete snapshot or
  discarding unrelated cached measurements.

The executable performs an unreported warm-up and prints the median of three
samples for each measurement.

Run an optimized build from the repository root:

```bash
swift run -c release ListViewKitBenchmarks
```

Results depend on hardware and toolchain versions. Compare changes using the
same machine, Swift version, and power conditions.
