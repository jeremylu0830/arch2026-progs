# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.
#
# The uint16_t arguments arrive zero-extended (RISC-V psABI), so bits 16..31
# of a0 and a1 are zero. All three are leaf functions: no stack, no saved
# registers.

    .text

# bf16_from_f32: Inf and NaN keep their top 16 bits; everything else adds
# 0x7FFF plus bit 16 (round to nearest, ties to even) and keeps the top half.
# The exponent test compares f32bits & 0x7F800000 with 0x7F800000 directly,
# which needs no shift.
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t1, 0x7F800             # exponent mask, 0x7F800000
    and     t0, a0, t1
    beq     t0, t1, .Lf32_top       # exponent 0xFF: Inf or NaN
    srli    t0, a0, 16
    andi    t0, t0, 1               # bit 16 decides a tie
    add     a0, a0, t0
    lui     t1, 0x8
    addi    t1, t1, -1              # 0x7FFF
    add     a0, a0, t1
.Lf32_top:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

# bf16_mul: the C version step by step, with the 8-bit by 8-bit product
# unrolled in place of a __mulsi3 call.
#
# Registers: t0 = ea, then e; t1 = eb; t2 = ma; t3 = mb; t4 = 0xFF;
# t5 = scratch; t6 = sign of the product (bit 15); a2 = product m.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t6, a0, a1
    srli    t6, t6, 15
    slli    t6, t6, 15              # sign = (a ^ b) & 0x8000
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # ea
    srli    t1, a1, 7
    andi    t1, t1, 0xFF            # eb
    andi    t2, a0, 0x7F            # ma
    andi    t3, a1, 0x7F            # mb
    li      t4, 0xFF
    beq     t0, t4, .Lmul_a_special # a first, then b, as the contract says
    beq     t1, t4, .Lmul_b_special
    slli    t5, a0, 17              # zero when a is +0 or -0
    beqz    t5, .Lmul_sign
    slli    t5, a1, 17
    beqz    t5, .Lmul_sign

    # Normalize: a denormal (exponent 0) shifts its fraction up to bit 7 and
    # counts the exponent down from 1; a normal gets its hidden one.
    bnez    t0, .Lmul_a_normal
    li      t0, 1
.Lmul_a_denorm:
    slli    t2, t2, 1
    addi    t0, t0, -1
    andi    t5, t2, 0x80
    beqz    t5, .Lmul_a_denorm
    j       .Lmul_b
.Lmul_a_normal:
    ori     t2, t2, 0x80
.Lmul_b:
    bnez    t1, .Lmul_b_normal
    li      t1, 1
.Lmul_b_denorm:
    slli    t3, t3, 1
    addi    t1, t1, -1
    andi    t5, t3, 0x80
    beqz    t5, .Lmul_b_denorm
    j       .Lmul_product
.Lmul_b_normal:
    ori     t3, t3, 0x80

    # m = ma * mb by shift and add over bits 0..6 of mb; bit 7 is always set
    # after normalization, so its term is added unconditionally.
.Lmul_product:
    li      a2, 0
    .irp    bit, 1, 2, 4, 8, 16, 32, 64
    andi    t5, t3, \bit
    beqz    t5, 1f
    add     a2, a2, t2
1:
    slli    t2, t2, 1
    .endr
    add     a2, a2, t2

    add     t0, t0, t1
    addi    t0, t0, -127            # e = ea + eb - 127
    srli    t5, a2, 15
    beqz    t5, .Lmul_shift7
    srli    a2, a2, 8               # product >= 2: one more bit, e + 1
    addi    t0, t0, 1
    j       .Lmul_range
.Lmul_shift7:
    srli    a2, a2, 7
.Lmul_range:
    bge     t0, t4, .Lmul_inf       # e >= 0xFF
    blez    t0, .Lmul_under         # e <= 0
    slli    t0, t0, 7
    andi    a2, a2, 0x7F            # truncate: the dropped bits are lost
    or      a0, t6, t0
    or      a0, a0, a2
    ret
.Lmul_under:
    li      t5, -6
    blt     t0, t5, .Lmul_sign      # below -6: zero
    andi    a2, a2, 0x7F            # the fraction, without the hidden one
    li      t5, 1
    sub     t5, t5, t0
    srl     a2, a2, t5              # shift right (1 - e) bits, exponent 0
    or      a0, t6, a2
    ret

.Lmul_a_special:
    bnez    t2, .Lmul_ret           # NaN a: a unchanged, already in a0
    slli    t5, a1, 17
    beqz    t5, .Lmul_qnan          # Inf times zero
    j       .Lmul_inf               # Inf, whatever b is
.Lmul_b_special:
    bnez    t3, .Lmul_ret_b         # NaN b: b unchanged
    slli    t5, a0, 17
    beqz    t5, .Lmul_qnan
.Lmul_inf:
    lui     t5, 0x8
    addi    t5, t5, -0x80           # 0x7F80
    or      a0, t6, t5
.Lmul_ret:
    ret
.Lmul_ret_b:
    mv      a0, a1
    ret
.Lmul_qnan:
    lui     a0, 0x8
    addi    a0, a0, -0x40           # 0x7FC0
    ret
.Lmul_sign:
    mv      a0, t6                  # zero with the product sign
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

# bf16_sqrt: the special cases of the contract, then the exponent halved and
# the significand rooted.
#
# The C version searches mid in [90, 256] for the largest mid with
# (mid * mid) >> 7 <= m. For integers that condition is
#     mid * mid < 128 * (m + 1)   <=>   mid * mid <= 128 * m + 127,
# so the answer is floor(sqrt(128 * m + 127)), the same number. Here it is
# found digit by digit, two bits of the radicand per step, with no multiply:
# m is at most 510, so N = 128 * m + 127 < 2^16 and eight steps starting
# at bit 1 << 14 cover it.
#
# m lies in [128, 510], so the root lies in [128, 255]: no renormalization
# is needed. The exponent lies in [63, 190]: neither Inf nor zero can result.
#
# Registers: t0 = exponent, t1 = significand m, then the remainder of N;
# t2 = the current bit; t3 = scratch; a1 = root.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exponent field
    andi    t1, a0, 0x7F            # fraction
    li      t2, 0xFF
    beq     t0, t2, .Lsqrt_special  # Inf or NaN
    slli    t3, a0, 16
    bltz    t3, .Lsqrt_neg          # sign bit set
    beqz    t0, .Lsqrt_zero         # +0 or a positive denormal

    addi    t0, t0, -127            # e
    ori     t1, t1, 0x80            # m with the hidden one
    andi    t3, t0, 1
    beqz    t3, .Lsqrt_even
    slli    t1, t1, 1               # odd e: m * 2 and e - 1
    addi    t0, t0, -1
.Lsqrt_even:
    srai    t0, t0, 1
    addi    t0, t0, 127             # new exponent

    slli    t1, t1, 7
    addi    t1, t1, 127             # N = 128 * m + 127
    li      a1, 0
    lui     t2, 0x4                 # 1 << 14
.Lsqrt_step:
    add     t3, a1, t2
    srli    a1, a1, 1
    bltu    t1, t3, .Lsqrt_next
    sub     t1, t1, t3
    add     a1, a1, t2
.Lsqrt_next:
    srli    t2, t2, 2
    bnez    t2, .Lsqrt_step

    slli    t0, t0, 7
    andi    a1, a1, 0x7F            # drop the hidden one
    or      a0, t0, a1
    ret

.Lsqrt_neg:
    slli    t3, a0, 17
    beqz    t3, .Lsqrt_zero         # -0 gives +0
.Lsqrt_qnan:
    lui     a0, 0x8
    addi    a0, a0, -0x40           # 0x7FC0
    ret
.Lsqrt_special:
    bnez    t1, .Lsqrt_ret          # NaN: unchanged
    slli    t3, a0, 16
    bltz    t3, .Lsqrt_qnan         # -Inf
.Lsqrt_ret:
    ret                             # +Inf: unchanged
.Lsqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
