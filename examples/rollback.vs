; A failed check discards the buffered write and preserves the old value.

    li      r1, 0x100
    li      r2, 0x100
    croot   c10, r1, r2, rw
    movi    r3, 7
    cstw    r3, c10, 0
    vlock

    vtry    failed, 2, 16
    movi    r4, 99
    cstw    r4, c10, 0
    clr     r5
    vchk    r5, 0x2222
    vic

failed:
    cldw    r6, c10, 0
    movi    r7, 7
    cmpeq   r8, r6, r7
    brz     r8, broken
    verr    r9
    halt

broken:
    trap    0xdead
