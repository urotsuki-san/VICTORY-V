# Security Policy

VICTORY-V is experimental RTL and does not have a supported security release.

Please report reproducible issues privately when possible. Include the source revision, tool version, program or waveform, expected behavior, and observed behavior.

Current security-relevant boundaries include capability checks, `VLOCK`, both `VTRY` entry paths, Victory Region rollback, commit preflight, and VRTU range and permission faults. Privilege modes, DMA isolation, tagged context save/restore, secure boot, and physical side-channel claims are not complete.

A post-publication fault is intentionally fatal. Once a write is externally visible, the core must not call the result a rollback.

The archived Euclid experiment is not part of the default FPGA image.
