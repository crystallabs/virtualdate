# Scheduler oracles and fuzzers

Long-running randomized and brute-force checks that compare `Scheduler#build`
and `VirtualDate#on?` against minute-/second-sampled ground-truth oracles.
They are too slow for `crystal spec`, so they live here and are meant for
release checks or a nightly CI job.

Run all of them with:

```sh
fuzz/run.sh
```

or one at a time with `crystal run --release fuzz/<name>.cr`.

| File | What it checks |
|------|----------------|
| `oracle1.cr` | 37 hand-picked rule shapes vs a minute-sampled occurrence oracle |
| `oracle2.cr` | 400 randomized rule/window/granularity cases + `max_candidates` cut logic |
| `oracle3.cr` | Second/millisecond rules vs 1s/100ms-sampled oracles |
| `oracle4.cr` | Long-run coalescing, locations, procs, bounds, shift/on overrides |
| `oracle5.cr` | Day-range oracle, degenerate windows, max_shift/max_shifts boundaries |
| `oracle6.cr` | 250 adversarial granularity/window-start combinations, 1s-sampled |
| `sched1.cr` | Targeted placement semantics: parallelism, priority, fixed, displacement + re-placement, dependency floors, deadlines, stagger, horizon edges |
| `sched2.cr` | Displacement guards, dependency errors, DST windows (America/New_York) |
| `fuzz_sched.cr` | 474 random multi-vdate schedules checked against invariants |
| `on_reachability_fuzz.cr` | `on?` inverse-reachability vs scanning `resolve` over a wider window |
