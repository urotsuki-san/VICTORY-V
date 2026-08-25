; A value loaded through a SECRET capability cannot control a branch.

    li      r1, 0x100
    movi    r2, 4
    croot   c10, r1, r2, rws
    movi    r3, 1
    cstw    r3, c10, 0
    vlock

    vtry    failed, 1, 16
    cldw    s4, c10, 0
    brz     s4, impossible
    vic

impossible:
    trap    0xbeef

failed:
    verr    r5
    halt
