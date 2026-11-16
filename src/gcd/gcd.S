# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.
#
# Stein's algorithm:
#   1. gcd(a, 0) = a and gcd(0, b) = b.
#   2. k = number of factors of two shared by a and b; divide both by 2^k.
#   3. Make a and b odd by shifting out their trailing zeros.
#   4. While a != b: subtract the smaller from the larger. The difference
#      of two odd numbers is even and nonzero, so shift its trailing zeros
#      out and it is odd again.
#   5. Return a << k.
#
# Registers: a0 = a, a1 = b, t0 = scratch bit, t1 = a | b, t2 = k.
# A leaf function: no stack, no saved registers.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .Lret_b             # gcd(0, b) = b
    beqz    a1, .Lret               # gcd(a, 0) = a, already in a0

    # Step 2: k = trailing zeros of (a | b), the shared factors of two.
    or      t1, a0, a1
    andi    t0, t1, 1
    li      t2, 0
    bnez    t0, .Lodd_a             # common case: one of them is odd, k = 0
.Lcount_k:
    srli    t1, t1, 1
    addi    t2, t2, 1
    andi    t0, t1, 1
    beqz    t0, .Lcount_k
    srl     a0, a0, t2
    srl     a1, a1, t2

    # Step 3: make a odd, then b odd.
.Lodd_a:
    andi    t0, a0, 1
    bnez    t0, .Lodd_b
.Lstrip_a0:
    srli    a0, a0, 1
    andi    t0, a0, 1
    beqz    t0, .Lstrip_a0
.Lodd_b:
    andi    t0, a1, 1
    bnez    t0, .Lloop
.Lstrip_b0:
    srli    a1, a1, 1
    andi    t0, a1, 1
    beqz    t0, .Lstrip_b0

    # Step 4: a and b are odd here. Each half of the loop ends with the
    # comparison that picks the next half, so no iteration needs a jump.
.Lloop:
    bltu    a1, a0, .Lbig_a         # a > b
    beq     a0, a1, .Ldone          # a == b: that is the odd part of gcd
.Lbig_b:                            # b > a: b = (b - a) without its zeros
    sub     a1, a1, a0
.Lstrip_b:
    srli    a1, a1, 1
    andi    t0, a1, 1
    beqz    t0, .Lstrip_b
    bltu    a1, a0, .Lbig_a
    bne     a0, a1, .Lbig_b
    j       .Ldone
.Lbig_a:                            # a > b: a = (a - b) without its zeros
    sub     a0, a0, a1
.Lstrip_a:
    srli    a0, a0, 1
    andi    t0, a0, 1
    beqz    t0, .Lstrip_a
    bltu    a1, a0, .Lbig_a
    bne     a0, a1, .Lbig_b

    # Step 5: put the shared factors of two back.
.Ldone:
    sll     a0, a0, t2
.Lret:
    ret
.Lret_b:
    mv      a0, a1
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
