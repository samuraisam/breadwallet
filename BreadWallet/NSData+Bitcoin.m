//
//  NSData+Bitcoin.m
//  BreadWallet
//
//  Created by Aaron Voisine on 10/9/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "NSData+Bitcoin.h"
#import "NSString+Bitcoin.h"

// bitwise left rotation
#define rol32(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

// basic sha1 functions
#define f1(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define f2(x, y, z) ((x) ^ (y) ^ (z))
#define f3(x, y, z) (((x) & (y)) | ((x) & (z)) | ((y) & (z)))

// basic sha1 operation
#define sha1(x, y, z) (t = rol32(a, 5) + (x) + e + (y) + (z), e = d, d = c, c = rol32(b, 30), b = a, a = t)

static void SHA1Compress(uint32_t *r, uint32_t *x)
{
    size_t i = 0;
    uint32_t a = r[0], b = r[1], c = r[2], d = r[3], e = r[4], t;
    
    for (; i < 16; i++) sha1(f1(b, c, d), 0x5a827999, (x[i] = CFSwapInt32BigToHost(x[i])));
    for (; i < 20; i++) sha1(f1(b, c, d), 0x5a827999, (x[i] = rol32(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1)));
    for (; i < 40; i++) sha1(f2(b, c, d), 0x6ed9eba1, (x[i] = rol32(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1)));
    for (; i < 60; i++) sha1(f3(b, c, d), 0x8f1bbcdc, (x[i] = rol32(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1)));
    for (; i < 80; i++) sha1(f2(b, c, d), 0xca62c1d6, (x[i] = rol32(x[i - 3] ^ x[i - 8] ^ x[i - 14] ^ x[i - 16], 1)));

    r[0] += a, r[1] += b, r[2] += c, r[3] += d, r[4] += e;
}

void SHA1(void *md, const void *data, size_t len)
{
    size_t i;
    uint32_t x[80], buf[] = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 }; // initial buffer values
    
    for (i = 0; i < len; i += 64) { // process data in 64 byte blocks
        memcpy(x, (const uint8_t *)data + i, (i + 64 < len) ? 64 : len - i);
        if (i + 64 > len) break;
        SHA1Compress(buf, x);
    }
    
    memset((uint8_t *)x + (len - i), 0, 64 - (len - i)); // clear remainder of x
    ((uint8_t *)x)[len - i] = 0x80; // append padding
    if (len - i >= 56) SHA1Compress(buf, x), memset(x, 0, 64); // length goes to next block
    *(uint64_t *)&x[14] = CFSwapInt64HostToBig((uint64_t)len*8); // append length in bits
    SHA1Compress(buf, x); // finalize
    for (i = 0; i < 5; i++) ((uint32_t *)md)[i] = CFSwapInt32HostToBig(buf[i]); // write to md
}

// bitwise right rotation
#define ror32(a, b) (((a) >> (b)) | ((a) << (32 - (b))))

// basic sha2 functions
#define ch(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define maj(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))

// basic sha256 functions
#define s0(x) (ror32((x), 2) ^ ror32((x), 13) ^ ror32((x), 22))
#define s1(x) (ror32((x), 6) ^ ror32((x), 11) ^ ror32((x), 25))
#define s2(x) (ror32((x), 7) ^ ror32((x), 18) ^ ((x) >> 3))
#define s3(x) (ror32((x), 17) ^ ror32((x), 19) ^ ((x) >> 10))

static void SHA256Compress(uint32_t *r, uint32_t *x)
{
    static const uint32_t k[] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    };
    
    size_t i;
    uint32_t a = r[0], b = r[1], c = r[2], d = r[3], e = r[4], f = r[5], g = r[6], h = r[7], t1, t2, w[64];
    
    for (i = 0; i < 16; i++) w[i] = CFSwapInt32BigToHost(x[i]);
    for (; i < 64; i++) w[i] = s3(w[i - 2]) + w[i - 7] + s2(w[i - 15]) + w[i - 16];
    
    for (i = 0; i < 64; i++) {
        t1 = h + s1(e) + ch(e, f, g) + k[i] + w[i];
        t2 = s0(a) + maj(a, b, c);
        h = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
    }
    
    r[0] += a, r[1] += b, r[2] += c, r[3] += d, r[4] += e, r[5] += f, r[6] += g, r[7] += h;
}

void SHA256(void *md, const void *data, size_t len)
{
    size_t i;
    uint32_t x[16], buf[] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }; // initial buffer values
    
    for (i = 0; i < len; i += 64) { // process data in 64 byte blocks
        memcpy(x, (const uint8_t *)data + i, (i + 64 < len) ? 64 : len - i);
        if (i + 64 > len) break;
        SHA256Compress(buf, x);
    }

    memset((uint8_t *)x + (len - i), 0, 64 - (len - i)); // clear remainder of x
    ((uint8_t *)x)[len - i] = 0x80; // append padding
    if (len - i >= 56) SHA256Compress(buf, x), memset(x, 0, 64); // length goes to next block
    *(uint64_t *)&x[14] = CFSwapInt64HostToBig((uint64_t)len*8); // append length in bits
    SHA256Compress(buf, x); // finalize
    for (i = 0; i < 8; i++) ((uint32_t *)md)[i] = CFSwapInt32HostToBig(buf[i]); // write to md
}

// bitwise right rotation
#define ror64(a, b) (((a) >> (b)) | ((a) << (64 - (b))))

// basic sha512 opeartions
#define S0(x) (ror64((x), 28) ^ ror64((x), 34) ^ ror64((x), 39))
#define S1(x) (ror64((x), 14) ^ ror64((x), 18) ^ ror64((x), 41))
#define S2(x) (ror64((x), 1) ^ ror64((x), 8) ^ ((x) >> 7))
#define S3(x) (ror64((x), 19) ^ ror64((x), 61) ^ ((x) >> 6))

static void SHA512Compress(uint64_t *r, uint64_t *x)
{
    static const uint64_t k[] = {
        0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
        0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
        0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
        0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
        0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
        0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
        0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
        0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
        0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
        0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
        0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
        0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
        0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
        0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
        0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817
    };
    
    size_t i;
    uint64_t a = r[0], b = r[1], c = r[2], d = r[3], e = r[4], f = r[5], g = r[6], h = r[7], t1, t2, w[80];
    
    for (i = 0; i < 16; i++) w[i] = CFSwapInt64BigToHost(x[i]);
    for (; i < 80; i++) w[i] = S3(w[i - 2]) + w[i - 7] + S2(w[i - 15]) + w[i - 16];
    
    for (i = 0; i < 80; i++) {
        t1 = h + S1(e) + ch(e, f, g) + k[i] + w[i];
        t2 = S0(a) + maj(a, b, c);
        h = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
    }
    
    r[0] += a, r[1] += b, r[2] += c, r[3] += d, r[4] += e, r[5] += f, r[6] += g, r[7] += h;
}

void SHA512(void *md, const void *data, size_t len)
{
    size_t i;
    uint64_t x[16], buf[] = { 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                              0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179 };
    
    for (i = 0; i < len; i += 128) { // process data in 128 byte blocks
        memcpy(x, (const uint8_t *)data + i, (i + 128 < len) ? 128 : len - i);
        if (i + 128 > len) break;
        SHA512Compress(buf, x);
    }
    
    memset((uint8_t *)x + (len - i), 0, 128 - (len - i)); // clear remainder of x
    ((uint8_t *)x)[len - i] = 0x80; // append padding
    if (len - i >= 112) SHA512Compress(buf, x), memset(x, 0, 128); // length goes to next block
    x[14] = 0, x[15] = CFSwapInt64HostToBig((uint64_t)len*8); // append length in bits
    SHA512Compress(buf, x); // finalize
    for (i = 0; i < 8; i++) ((uint64_t *)md)[i] = CFSwapInt64HostToBig(buf[i]); // write to md
}

// basic ripemd functions
#define f(x, y, z) ((x) ^ (y) ^ (z))
#define g(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define h(x, y, z) (((x) | ~(y)) ^ (z))
#define i(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define j(x, y, z) ((x) ^ ((y) | ~(z)))

// basic ripemd operation
#define rmd(a, b, c, d, e, f, g, h, i, j) ((a) = rol32((f) + (b) + CFSwapInt32LittleToHost(c) + (d), (e)) + (g),\
                                           (f) = (g), (g) = (h), (h) = rol32((i), 10), (i) = (j), (j) = (a))

static void RMDcompress(uint32_t *r, uint32_t *x)
{
    // left line
    static const uint32_t rl1[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }, // round 1, id
                          rl2[] = { 7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8 }, // round 2, rho
                          rl3[] = { 3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12 }, // round 3, rho^2
                          rl4[] = { 1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2 }, // round 4, rho^3
                          rl5[] = { 4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13 }; // round 5, rho^4
    // right line
    static const uint32_t rr1[] = { 5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12 }, // round 1, pi
                          rr2[] = { 6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2 }, // round 2, rho pi
                          rr3[] = { 15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13 }, // round 3, rho^2 pi
                          rr4[] = { 8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14 }, // round 4, rho^3 pi
                          rr5[] = { 12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11 }; // round 5, rho^4 pi
    // left line shifts
    static const uint32_t sl1[] = { 11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8 }, // round 1
                          sl2[] = { 7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12 }, // round 2
                          sl3[] = { 11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5 }, // round 3
                          sl4[] = { 11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12 }, // round 4
                          sl5[] = { 9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6 }; // round 5
    // right line shifts
    static const uint32_t sr1[] = { 8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6 }, // round 1
                          sr2[] = { 9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11 }, // round 2
                          sr3[] = { 9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5 }, // round 3
                          sr4[] = { 15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8 }, // round 4
                          sr5[] = { 8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11 }; // round 5

    size_t i;
    uint32_t al = r[0], bl = r[1], cl = r[2], dl = r[3], el = r[4], ar = al, br = bl, cr = cl, dr = dl, er = el, t;

    for (i = 0; i < 16; i++) rmd(t, f(bl, cl, dl), x[rl1[i]], 0x00000000, sl1[i], al, el, dl, cl, bl); // round 1 left
    for (i = 0; i < 16; i++) rmd(t, j(br, cr, dr), x[rr1[i]], 0x50a28be6, sr1[i], ar, er, dr, cr, br); // round 1 right
    for (i = 0; i < 16; i++) rmd(t, g(bl, cl, dl), x[rl2[i]], 0x5a827999, sl2[i], al, el, dl, cl, bl); // round 2 left
    for (i = 0; i < 16; i++) rmd(t, i(br, cr, dr), x[rr2[i]], 0x5c4dd124, sr2[i], ar, er, dr, cr, br); // round 2 right
    for (i = 0; i < 16; i++) rmd(t, h(bl, cl, dl), x[rl3[i]], 0x6ed9eba1, sl3[i], al, el, dl, cl, bl); // round 3 left
    for (i = 0; i < 16; i++) rmd(t, h(br, cr, dr), x[rr3[i]], 0x6d703ef3, sr3[i], ar, er, dr, cr, br); // round 3 right
    for (i = 0; i < 16; i++) rmd(t, i(bl, cl, dl), x[rl4[i]], 0x8f1bbcdc, sl4[i], al, el, dl, cl, bl); // round 4 left
    for (i = 0; i < 16; i++) rmd(t, g(br, cr, dr), x[rr4[i]], 0x7a6d76e9, sr4[i], ar, er, dr, cr, br); // round 4 right
    for (i = 0; i < 16; i++) rmd(t, j(bl, cl, dl), x[rl5[i]], 0xa953fd4e, sl5[i], al, el, dl, cl, bl); // round 5 left
    for (i = 0; i < 16; i++) rmd(t, f(br, cr, dr), x[rr5[i]], 0x00000000, sr5[i], ar, er, dr, cr, br); // round 5 right
    
    t = r[1] + cl + dr; // final result for r[0]
    r[1] = r[2] + dl + er, r[2] = r[3] + el + ar, r[3] = r[4] + al + br, r[4] = r[0] + bl + cr, r[0] = t; // combine
}

// ripemd-160 hash function: http://homes.esat.kuleuven.be/~bosselae/ripemd160.html
void RMD160(void *md, const void *data, size_t len)
{
    size_t i;
    uint32_t x[16], buf[] = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 }; // initial buffer values
    
    for (i = 0; i <= len; i += 64) { // process data in 64 byte blocks
        memcpy(x, (const uint8_t *)data + i, (i + 64 < len) ? 64 : len - i);
        if (i + 64 > len) break;
        RMDcompress(buf, x);
    }
    
    memset((uint8_t *)x + (len - i), 0, 64 - (len - i)); // clear remainder of x
    ((uint8_t *)x)[len - i] = 0x80; // append padding
    if (len - i >= 56) RMDcompress(buf, x), memset(x, 0, 64); // length goes to next block
    *(uint64_t *)&x[14] = CFSwapInt64HostToLittle((uint64_t)len*8); // append length in bits
    RMDcompress(buf, x); // finalize
    for (i = 0; i < 5; i++) ((uint32_t *)md)[i] = CFSwapInt32HostToLittle(buf[i]); // write to md
}

// HMAC(key, data) = hash((key xor opad) || hash((key xor ipad) || data))
// opad = 0x5c5c5c...5c5c
// ipad = 0x363636...3636
void HMAC(void *md, void (*hash)(void *, const void *, size_t), size_t hlen, const void *key, size_t klen,
          const void *data, size_t dlen)
{
    size_t blen = (hlen > 32) ? 128 : 64;
    uint8_t k[hlen], kipad[blen + dlen], kopad[blen + hlen];
    
    if (klen > blen) hash(k, key, klen), key = k, klen = sizeof(k);
    memset(kipad, 0, blen);
    memcpy(kipad, key, klen);
    for (size_t i = 0; i < blen/8; i++) ((uint64_t *)kipad)[i] ^= 0x3636363636363636;
    memset(kopad, 0, blen);
    memcpy(kopad, key, klen);
    for (size_t i = 0; i < blen/8; i++) ((uint64_t *)kopad)[i] ^= 0x5c5c5c5c5c5c5c5c;
    memcpy(kipad + blen, data, dlen);
    hash(kopad + blen, kipad, sizeof(kipad));
    hash(md, kopad, sizeof(kopad));
    
    memset(k, 0, sizeof(k));
    memset(kipad, 0, blen);
    memset(kopad, 0, blen);
}

// dk = T1 || T2 || ... || Tdklen/hlen
// Ti = U1 xor U2 xor ... xor Urounds
// U1 = hmac_hash(pw, salt || INT32_BE(i))
// U2 = hmac_hash(pw, U1)
// ...
// Urounds = hmac_hash(pw, Urounds-1)
void PBKDF2(void *dk, size_t dklen, void (*hash)(void *, const void *, size_t), size_t hlen,
            const void *pw, size_t pwlen, const void *salt, size_t slen, unsigned rounds)
{
    uint8_t s[slen + sizeof(unsigned)], U[hlen], T[hlen];
    uint32_t i, j;
    
    memcpy(s, salt, slen);
    
    for (i = 0; i < (dklen + hlen - 1)/hlen; i++) {
        *(uint32_t *)(s + slen) = CFSwapInt32HostToBig(i + 1);
        HMAC(U, hash, hlen, pw, pwlen, s, sizeof(s)); // U1 = hmac_hash(pw, salt || INT32_BE(i))
        memcpy(T, U, sizeof(U));

        for (unsigned r = 1; r < rounds; r++) {
            HMAC(U, hash, hlen, pw, pwlen, U, sizeof(U)); // Urounds = hmac_hash(pw, Urounds-1)
            for (j = 0; j < hlen/4; j++) ((uint32_t *)T)[j] ^= ((uint32_t *)U)[j]; // Ti = U1 xor U2 xor ... xor Urounds
        }

        // dk = T1 || T2 || ... || Tdklen/hlen
        memcpy((uint8_t *)dk + i*hlen, T, (i*hlen + hlen <= dklen) ? hlen : dklen % hlen);
    }
    
    memset(s, 0, sizeof(s));
    memset(U, 0, sizeof(U));
    memset(T, 0, sizeof(T));
}

@implementation NSData (Bitcoin)

+ (instancetype)dataWithUInt256:(UInt256)n
{
    return [NSData dataWithBytes:&n length:sizeof(n)];
}

+ (instancetype)dataWithUInt160:(UInt160)n
{
    return [NSData dataWithBytes:&n length:sizeof(n)];
}

+ (instancetype)dataWithBase58String:(NSString *)b58str
{
    return b58str.base58ToData;
}

- (UInt160)SHA1
{
    UInt160 sha1;

    SHA1(&sha1, self.bytes, self.length);
    return sha1;
}

- (UInt256)SHA256
{
    UInt256 sha256;
    
    SHA256(&sha256, self.bytes, self.length);
    return sha256;
}

- (UInt256)SHA256_2
{
    UInt256 sha256;
    
    SHA256(&sha256, self.bytes, self.length);
    SHA256(&sha256, &sha256, sizeof(sha256));
    return sha256;
}

- (UInt512)SHA512
{
    UInt512 sha512;
    
    SHA512(&sha512, self.bytes, self.length);
    return sha512;
}

- (UInt160)RMD160
{
    UInt160 rmd160;
    
    RMD160(&rmd160, self.bytes, (size_t)self.length);
    return rmd160;
}

- (UInt160)hash160
{
    UInt256 sha256;
    UInt160 rmd160;
    
    SHA256(&sha256, self.bytes, self.length);
    RMD160(&rmd160, &sha256, sizeof(sha256));
    return rmd160;
}

- (NSData *)reverse
{
    NSUInteger len = self.length;
    NSMutableData *d = [NSMutableData dataWithLength:len];
    uint8_t *b1 = d.mutableBytes;
    const uint8_t *b2 = self.bytes;
    
    for (NSUInteger i = 0; i < len; i++) {
        b1[i] = b2[len - i - 1];
    }
    
    return d;
}

- (uint8_t)UInt8AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint8_t)) return 0;
    return *((const uint8_t *)self.bytes + offset);
}

- (uint16_t)UInt16AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint16_t)) return 0;
    return CFSwapInt16LittleToHost(*(const uint16_t *)((const uint8_t *)self.bytes + offset));
}

- (uint32_t)UInt32AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint32_t)) return 0;
    return CFSwapInt32LittleToHost(*(const uint32_t *)((const uint8_t *)self.bytes + offset));
}

- (uint64_t)UInt64AtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(uint64_t)) return 0;
    return CFSwapInt64LittleToHost(*(const uint64_t *)((const uint8_t *)self.bytes + offset));
}

- (uint64_t)varIntAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    uint8_t h = [self UInt8AtOffset:offset];

    switch (h) {
        case VAR_INT16_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint16_t);
            return [self UInt16AtOffset:offset + 1];
            
        case VAR_INT32_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint32_t);
            return [self UInt32AtOffset:offset + 1];
            
        case VAR_INT64_HEADER:
            if (length) *length = sizeof(h) + sizeof(uint64_t);
            return [self UInt64AtOffset:offset + 1];
            
        default:
            if (length) *length = sizeof(h);
            return h;
    }
}

- (UInt256)hashAtOffset:(NSUInteger)offset
{
    if (self.length < offset + sizeof(UInt256)) return UINT256_ZERO;
    return *(const UInt256 *)((const char *)self.bytes + offset);
}

- (NSString *)stringAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    NSUInteger ll, l = (NSUInteger)[self varIntAtOffset:offset length:&ll];
    
    if (length) *length = ll + l;
    if (ll == 0 || self.length < offset + ll + l) return nil;
    return [[NSString alloc] initWithBytes:(const char *)self.bytes + offset + ll length:l
            encoding:NSUTF8StringEncoding];
}

- (NSData *)dataAtOffset:(NSUInteger)offset length:(NSUInteger *)length
{
    NSUInteger ll, l = (NSUInteger)[self varIntAtOffset:offset length:&ll];
    
    if (length) *length = ll + l;
    if (ll == 0 || self.length < offset + ll + l) return nil;
    return [self subdataWithRange:NSMakeRange(offset + ll, l)];
}

// an array of NSNumber and NSData objects representing each script element
- (NSArray *)scriptElements
{
    NSMutableArray *a = [NSMutableArray array];
    const uint8_t *b = (const uint8_t *)self.bytes;
    NSUInteger l, length = self.length;
    
    for (NSUInteger i = 0; i < length; i += l) {
        if (b[i] > OP_PUSHDATA4) {
            l = 1;
            [a addObject:@(b[i])];
            continue;
        }
        
        switch (b[i]) {
            case 0:
                l = 1;
                [a addObject:@(0)];
                continue;

            case OP_PUSHDATA1:
                i++;
                if (i + sizeof(uint8_t) > length) return a;
                l = b[i];
                i += sizeof(uint8_t);
                break;

            case OP_PUSHDATA2:
                i++;
                if (i + sizeof(uint16_t) > length) return a;
                l = CFSwapInt16LittleToHost(*(uint16_t *)&b[i]);
                i += sizeof(uint16_t);
                break;

            case OP_PUSHDATA4:
                i++;
                if (i + sizeof(uint32_t) > length) return a;
                l = CFSwapInt32LittleToHost(*(uint32_t *)&b[i]);
                i += sizeof(uint32_t);
                break;

            default:
                l = b[i];
                i++;
                break;
        }
        
        if (i + l > length) return a;
        [a addObject:[NSData dataWithBytes:&b[i] length:l]];
    }
    
    return a;
}

// returns the opcode used to store the receiver in a script (i.e. OP_PUSHDATA1)
- (int)intValue
{
    if (self.length < OP_PUSHDATA1) return (int)self.length;
    else if (self.length <= UINT8_MAX) return OP_PUSHDATA1;
    else if (self.length <= UINT16_MAX) return OP_PUSHDATA2;
    else return OP_PUSHDATA4;
}

- (NSString *)base58String
{
    return [NSString base58WithData:self];
}

@end
