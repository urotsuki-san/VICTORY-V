# Euclid Plane

> The cheap guess decides where to look. The exact side decides when to stop.

## Status

Euclid is an archived experiment. The active files are all under this directory:

- `euclid.py` — executable model;
- `test_euclid.py` — reference and guard checks;
- `rtl/vv_euclid_a0.sv` — fixed-width hardware slice;
- `tb/vv_euclid_a0_tb.sv` — standalone RTL regression.

There is no board wrapper in the default Tang 138K image, no CPU-visible ABI, and no measured Gowin speedup. Run it only through `make experiment-euclid`.

## What it was trying to do

A conventional calculation often computes a complete number and then asks a yes/no question about it. Euclid asked whether the decision could become exact earlier.

For the first experiment the question was nearest neighbour.

```text
candidate A: distance is somewhere in [12, 18]
candidate B: distance is somewhere in [40, 90]

18 < 40
```

At that point B cannot win. Finishing every remaining term would produce more arithmetic, not a different answer.

The accepted decision remains exact. The shortcut is in how much work is needed to prove it.

## Model and RTL

The Python model explores candidate buds, proof debt, guarded regions, and seed-dependent scheduling. The RTL is deliberately smaller:

| Property | Python model | Euclid-A0 RTL |
|---|---|---|
| candidates | general small sets | 4 |
| dimensions | general small sets | up to 8 |
| coordinates | Python integers | signed 8-bit |
| accepted winner | exact | exact |
| work ordering | seed + hints | seed-selected coordinate order |
| early stop | exact bound proof | partial squared-distance elimination |
| guard | geometric experiment | one conservative entry |

The narrow RTL was meant to earn a larger design through measurement. That measurement has not happened, so the larger fabric remains a note rather than a roadmap item.

## Work selection

The scheduling side may guess wrong about what looks promising. A bad guess may cost cycles; it must not change the winner.

The seed is therefore a scheduling input, not a correctness input. Tests should show different traces with the same accepted result.

## Guarded reuse

The experiment called its guard cache “Atlas”. The name is less important than the rule:

> a reused result is valid only while a guard proves that it still applies.

A false hit is a correctness defect. This discipline survived in VRTU, where bounds, permissions, and generation must still prove the reused translation.

## What moved into the processor

The nearest-neighbour datapath did not move into the CPU. Three ideas did:

- reject a request as soon as failure is exact;
- reuse a previous result only behind a live guard;
- keep refinement bounded and visible.

VRTU uses the first two. Victory Contracts use the third.

## Measurements that would matter

A future revival would need numbers from this implementation:

- cycles to an exact decision;
- arithmetic terms visited versus a complete calculation;
- guarded-hit rate;
- LUT/FF/BSRAM/DSP cost;
- Fmax after Gowin place-and-route;
- energy per exact decision, if power measurement becomes available;
- zero wrong decisions in the exact channel.

No cited paper supplies those numbers for VICTORY-V.

## Archive boundary

The experiment may be useful as a workload or a source of small ideas. It should not quietly return to the FPGA image, acquire an opcode, or become a product claim without a fresh contract, tests, and measurements.

The strange part of VICTORY-V should stay measurable. A bigger diagram is not progress if the small circuit has not earned it.
