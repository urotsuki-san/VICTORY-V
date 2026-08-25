# Provisional VV32-A0 ABI

This ABI is a planning contract for hand-written assembly and the future compiler port. It is not yet backed by a C compiler and may change before the first stable profile.

## Register convention

| Registers | Role | Preservation |
|---|---|---|
| `r0` | constant zero | fixed |
| `r1`–`r4` | arguments; `r1`–`r2` return values | caller-saved |
| `r5`–`r12` | temporaries | caller-saved |
| `r13`–`r20` | saved values | callee-saved |
| `r21`–`r28` | additional temporaries / platform use | caller-saved for A0 |
| `r29` / `c29` | stack cursor capability | callee-owned |
| `r30` / `c30` | optional frame capability | callee-saved |
| `r31` | link register | caller-saved |

A callee that preserves a capability register must preserve its value, bounds, permissions, valid tag, and secret tag. Ordinary integer stores cannot do this in A0, so a general compiler/RTOS context ABI remains blocked until tagged capability save/restore is specified.

## Stack

- stack grows toward lower addresses;
- stack pointer is 16-byte aligned at a public call boundary;
- `c29` must carry `R|W` permission and bounds for the active stack object;
- return addresses stay in `r31` unless software explicitly stores them as integers;
- an A0 function must not assume that a failed Victory Region restores stack-pointer registers.

## Calls

```asm
    call function
    ; r31 receives the following PC

function:
    ; body
    ret
```

Indirect calls use `JALR`. A0 does not yet implement executable capabilities or landing-pad enforcement, so control-flow integrity is not claimed.

## Trap entry

Hardware records `VEPC`, `VCAUSE`, and `VBADADDR`, disables external interrupts, and transfers to `VTVEC`. A handler returns with `VRET`.

The complete trap-frame layout is deferred until capability metadata has an architectural save format.
