#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    int k = 0;
    if (a == 0 && b == 0)
        return 0;
    if (a == 0 && b != 0)
        return b;
    if (a != 0 && b == 0)
        return a;

    while (!(a & 1) && !(b & 1)) {
        a = a >> 1;
        b = b >> 1;
        k++;
    }

    while (b != 0) {
        while (!(a & 1)) {
            a = a >> 1;
        }
        while (!(b & 1)) {
            b = b >> 1;
        }
        if (a == b)
            return a << k;
        if (a > b) {
            a = a - b;
        } else {
            b = b - a;
            uint32_t temp = a;
            a = b;
            b = temp;
        }
    }
    return 0;
}
