# Euclid experiment

Euclid is kept here as research history and as an Anytime Ladder workload. It is not part of the default Tang 138K image, the VICTORY-V ISA, or the normal RTL regression.

Run it explicitly:

```console
make experiment-euclid
```

The directory contains the archived model, RTL, testbench, and notes. The reusable ideas were smaller than the accelerator: exact early rejection, guarded reuse, and work that refines only while the result can still change.

See [`EUCLID_PLANE.md`](EUCLID_PLANE.md) for the original direction and the current archive boundary.
