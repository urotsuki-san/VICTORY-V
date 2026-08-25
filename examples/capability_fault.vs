; An out-of-bounds store becomes a bounded region failure, not corruption.

    li      r1, 0x100
    movi    r2, 4
    croot   c10, r1, r2, rw
    movi    r3, 11
    cstw    r3, c10, 0
    vlock

    vtry    failed, 2, 16
    movi    r4, 99
    cstw    r4, c10, 4
    vic

failed:
    cldw    r5, c10, 0
    movi    r6, 11
    cmpeq   r7, r5, r6
    brz     r7, broken
    verr    r8
    halt

broken:
    trap    0xdead
