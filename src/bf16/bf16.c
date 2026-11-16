#include "bf16.h"


uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits >> 23 & 0xFF) == 0xFF) {
        return f32bits >> 16;
    }
    uint32_t b16 = (f32bits & 0x00010000) >> 16;

    return (f32bits + 0x7FFF + b16) >> 16;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    if ((a >> 7 & 0xFF) == 0xFF) {
        if (a & 0x7F)
            return a;
        if ((b & 0x7FFF) == 0)
            return 0x7FC0;
        return ((a & 0x8000) ^ (b & 0x8000)) | 0x7F80;
    }

    if ((b >> 7 & 0xFF) == 0xFF) {
        if (b & 0x7F)
            return b;
        if ((a & 0x7FFF) == 0)
            return 0x7FC0;
        return ((a & 0x8000) ^ (b & 0x8000)) | 0x7F80;
    }

    if ((b & 0x7FFF) == 0 || (a & 0x7FFF) == 0) {
        return ((a & 0x8000) ^ (b & 0x8000));
    }

    uint16_t sign = (a ^ b) & 0x8000;
    int16_t ea = a >> 7 & 0xFF, eb = b >> 7 & 0xFF;
    uint32_t ma = a & 0x7F, mb = b & 0x7F;

    if (ea == 0) {
        ea = 1;
        while (!(ma & 0x80)) {
            ea--;
            ma = ma << 1;
        }
    } else {
        ma = ma | 0x80;
    }

    if (eb == 0) {
        eb = 1;
        while (!(mb & 0x80)) {
            eb--;
            mb = mb << 1;
        }
    } else {
        mb = mb | 0x80;
    }



    uint32_t m = ma * mb;
    int16_t e = ea + eb - 127;

    if ((m & 0x8000) == 0x8000) {
        m = m >> 8;
        e++;
    } else {
        m = m >> 7;
    }

    if (e >= 0xFF)
        return sign | 0x7F80;

    if (e <= 0) {
        if (e < -6)
            return sign;
        m = (m & 0x7F) >> (1 - e);
        e = 0;
    }

    return sign | (e << 7) | (m & 0x7F);
}

uint16_t bf16_sqrt(uint16_t a)
{
    int sign = a >> 15;
    int exp = a >> 7 & 0xFF;
    uint32_t mant = a & 0x7F;

    if (exp == 0xFF) {
        if (mant != 0)
            return a;
        if (sign == 1)
            return 0x7FC0;
        return a;
    }
    if (exp == 0 && mant == 0)
        return 0;
    if (sign == 1)
        return 0x7FC0;
    if (exp == 0)
        return 0;

    int e = exp - 127;
    uint32_t m = mant | 0x80;
    int new_exp;
    if (e & 1) {
        m = m << 1;
        new_exp = ((e - 1) >> 1) + 127;
    } else {
        new_exp = (e >> 1) + 127;
    }

    uint32_t low = 128, high = 256, result = 128;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) >> 7;
        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    if (result >= 256) {
        result = result >> 1;
        new_exp++;
    }
    if (new_exp >= 0xFF)
        return 0x7F80;
    if (new_exp <= 0)
        return 0;

    return (new_exp << 7) | (result & 0x7F);
}
