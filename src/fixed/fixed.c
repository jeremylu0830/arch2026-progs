#include "fixed.h"


uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        (*n)++;
    }

    return a;
}


uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    uint32_t c = a & b;
    a = (a ^ b) >> 1;
    a = a + c;
    return a;
}

int32_t q_mul(int32_t a, int32_t b)
{
    int32_t aH = a >> 16, bH = b >> 16;
    uint32_t aL = a & 0xFFFF, bL = b & 0xFFFF;

    uint64_t p = ((uint64_t) (int64_t) (aH * bH) << 32) +
                 ((uint64_t) (int64_t) (aH * (int32_t) bL) << 16) +
                 ((uint64_t) (int64_t) ((int32_t) aL * bH) << 16) +
                 (uint64_t) (int64_t) (aL * bL);

    return (int32_t) ((p + 524288) >> 20);
}
