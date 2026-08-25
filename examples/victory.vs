; VICTORY-V baseline demonstration.
; The memory update becomes visible only after Victory Integrity Commit.

    li      r1, 0x100
    li      r2, 0x100
    croot   c10, r1, r2, rw
    vlock

    vtry    failed, 4, 32
    movi    r3, 1
    movi    r4, 1
    add     r5, r3, r4
    movi    r6, 2
    cmpeq   r7, r5, r6
    cstw    r5, c10, 0
    vchk    r7, 0x1001
    vic

    cldw    r8, c10, 0
    movi    r9, 2
    cmpeq   r11, r8, r9
    brz     r11, broken
    halt

failed:
    verr    r12
    halt

broken:
    trap    0xdead
