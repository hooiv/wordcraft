# Evaluating Kache locally

GitHub Actions is unavailable for this repository because of billing, so do not use a hosted
workflow to evaluate build caching. `scripts/benchmark-kache.ps1` runs the same WordCraft workload
locally in either baseline mode or with Kache and saves timings under `target/benchmark-kache/`
(ignored build output; reports are not committed).

Kache is a compiler cache that acts as `RUSTC_WRAPPER`. It does not improve WordCraft's runtime
typing or pagination directly; it may reduce the time spent rebuilding Rust crates. Kache supports
Windows; its documented Cargo install requires Rust 1.95 or newer. See the
[Kache README](https://github.com/kunobi-ninja/kache) for current install choices and commands.

## Setup

Install Kache using the official instructions, then check its configuration. `kache init` modifies
your user Cargo configuration, so review it before applying; the benchmark script itself does not
edit Cargo configuration. Check the install with:

```powershell
kache --version
kache doctor
```

Run the measurements from a clean WordCraft checkout with no unrelated builds running. Start with
`Check`: it is shorter and avoids the full CI workload while checking all workspace crates.

```powershell
# Ordinary rustc baseline (Kache is explicitly bypassed)
./scripts/benchmark-kache.ps1 -Mode Baseline -Workload Check -Repeat 3

# Kache-enabled warm-cache measurements; run after baseline
./scripts/benchmark-kache.ps1 -Mode Kache -Workload Check -Repeat 3
```

For the complete project gate, substitute `-Workload Ci`. That runs `cargo xtask ci` and is much
more expensive. Each script invocation records the exact revision, mode, workload, iteration,
timestamp and elapsed seconds in JSON. The Kache mode also prints `kache stats --last-build`.

## Reading results

Compare medians, not the fastest individual run. Keep the same revision, toolchain, workload,
machine state and target directory for each comparison. Report at least the elapsed time and the
cache hit/miss breakdown; note the Kache version. A valid evaluation should show repeatable time
savings without any test, clippy, asset, layering or WebAssembly-check failures.

For fair cold/warm measurement, treat the first Kache build after an empty or unused cache as a
cold run and later identical builds as warm runs. Do not clear your entire Kache store just for this
test: it may be shared with other worktrees or projects. Use `kache list`, `kache stats`, and the
official `kache clean --dry-run` guidance before any cache cleanup. Run baseline and Kache modes in
alternating blocks if the machine is noisy, and record other heavy activity.

## Scope and limitations

- This is a local measurement harness, not CI automation. Hosted GitHub Actions are intentionally
  not required.
- The default workload is `cargo xtask ci`, matching the project's local six-gate suite. `Check`
  is available for a quicker first comparison.
- Kache is opt-in and is not configured in WordCraft's committed `.cargo/config.toml` or enabled
  for release signing.
- The script temporarily sets process-scoped environment variables and restores the wrapper after
  completion; it does not change global Cargo settings. Kache may still have been configured
  globally by the user during setup.
