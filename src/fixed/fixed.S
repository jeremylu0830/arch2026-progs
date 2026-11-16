# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.
#
# All four are leaf functions: no stack, no saved registers.

    .text

# op1: a + b from AND, XOR and shift. Each pass computes the carry word
# (a & b) << 1 and the sum without carries a ^ b, until the carry is zero.
# The loop is unrolled twice, so a pair of passes costs one counter update;
# leaving after the first pass of a pair adds the missing one.
#
# Registers: a0 = a, a1 = b (the carry), a2 = n, t0 = a & b, t1 = passes.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t1, 0
    beqz    a1, .Lop1_store         # op1(x, 0) = x in 0 passes
.Lop1_pair:
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, .Lop1_odd           # done after the first pass of the pair
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 2
    bnez    a1, .Lop1_pair
.Lop1_store:
    sw      t1, 0(a2)
    ret
.Lop1_odd:
    addi    t1, t1, 1
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

# op2: a - b modulo 2^32 is one instruction.
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

# op3: floor((a + b) / 2) without overflow. a + b = (a ^ b) + 2 (a & b), so
# half of it is ((a ^ b) >> 1) + (a & b), and neither term can carry out.
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

# q_mul: (a * b + 2^19) >> 20, keeping the low 32 bits.
#
#   1. Multiply the magnitudes |a| and |b| as unsigned numbers and remember
#      the sign of the product, a ^ b. |INT32_MIN| = 2^31 is still exact as
#      an unsigned value.
#   2. The smaller magnitude x is the multiplier: the loop runs once per bit
#      of x, up to its highest set bit, and stops as soon as x is zero.
#   3. For each set bit i of x, add m << i to the 64-bit sum hi:lo. Its low
#      word is m << i, its high word is (m >> 1) >> (31 - i); the two shifts
#      avoid a shift by 32, which RV32I would take as a shift by 0. 31 - i is
#      i ^ 31 for i in 0..31.
#   4. Negate the 64-bit sum if the signs differed, add 2^19, and take bits
#      20..51: (lo >> 20) | (hi << 12). Whether hi is shifted arithmetically
#      does not matter, the bits it would decide are dropped.
#
# Registers: a0 = x (multiplier), a1 = m (multiplicand), a2:a3 = lo:hi,
# a4 = i, a5 = sign in bit 31, a6 = m >> 1, t0..t2 = scratch.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor     a5, a0, a1              # bit 31: the product is negative
    srai    t0, a0, 31              # |a| = (a ^ s) - s with s = a >> 31
    xor     a0, a0, t0
    sub     a0, a0, t0
    srai    t0, a1, 31              # |b|
    xor     a1, a1, t0
    sub     a1, a1, t0
    bgeu    a1, a0, .Lq_sorted      # x = min(|a|, |b|), m = max
    mv      t0, a0
    mv      a0, a1
    mv      a1, t0
.Lq_sorted:
    li      a2, 0                   # lo
    li      a3, 0                   # hi
    li      a4, 0                   # i
    srli    a6, a1, 1
    beqz    a0, .Lq_sign
.Lq_bit:
    andi    t0, a0, 1
    beqz    t0, .Lq_next
    sll     t1, a1, a4              # low word of m << i
    xori    t2, a4, 31
    srl     t2, a6, t2              # high word of m << i
    add     a2, a2, t1
    sltu    t1, a2, t1              # carry out of the low word
    add     a3, a3, t2
    add     a3, a3, t1
.Lq_next:
    srli    a0, a0, 1
    addi    a4, a4, 1
    bnez    a0, .Lq_bit
.Lq_sign:
    bgez    a5, .Lq_round
    snez    t0, a2                  # -(hi:lo) = (-hi - (lo != 0)):(-lo)
    neg     a2, a2
    neg     a3, a3
    sub     a3, a3, t0
.Lq_round:
    lui     t0, 0x80                # 2^19, half a unit
    add     a2, a2, t0
    sltu    t0, a2, t0
    add     a3, a3, t0
    srli    a2, a2, 20
    slli    a3, a3, 12
    or      a0, a2, a3
    ret
    .size   q_mul_asm, .-q_mul_asm
