# VICTORY-V Architecture Family

`VV32-A0` is the source architecture. `VV64-A0` widens the machine and the implementation envelope without replacing it.

## Family rule

> Work declares the state and memory it may consume. Exceeding the declaration restores the entry state.

Both widths keep capability-checked memory, monotonic authority, Victory Region rollback, explicit failure, root lock, and a non-speculative baseline.

`VTRY` is the family-level Region entry. The inline form carries a small contract in the instruction. The prepared form is admitted by `VPREP` and entered with `VTRY cToken, fail`. Both reach the same checkpoint. The encodings are `VTRY.I` and `VTRY.C`; there is no second entry mnemonic in the public ISA.

## Profiles

| Profile | Role | Contract capacity |
|---|---|---|
| VV32-A0 | budget root, monitor, deterministic I/O | compact |
| VV64-A0/P0 | main no-MMU Linux core | 32 capability entries, 8 stores, 4 VRTU ranges |
| VV64-A0/E0 | bounded worker | 8 capability entries, 2 stores, 2 VRTU ranges |

P0 and E0 use the same ISA and eventual ABI. Their heterogeneity is the size of contract they can admit.

## Translation path

`VV64-L0-flat` uses VRTU and `CONFIG_MMU=n`. The descriptor bank is the exact mapping; there is no refill trap or page walk. `VV64-L0-paged` remains a later profile for workloads that genuinely need sparse virtual memory.

## Experiment boundary

The former Euclid block is retained under `experiments/euclid/`. It is not a family member, FPGA component, opcode page, or default test. Guarded reuse and exact early rejection survived in VRTU; the nearest-neighbour datapath did not.
