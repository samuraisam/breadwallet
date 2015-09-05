//
//  BRBIP32Sequence.m
//  BreadWallet
//
//  Created by Aaron Voisine on 7/19/13.
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

#import "BRBIP32Sequence.h"
#import "BRKey.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"

#define BIP32_HARD 0x80000000u
#define BIP32_SEED_KEY "Bitcoin seed"
#define BIP32_XPRV "\x04\x88\xAD\xE4"
#define BIP32_XPUB "\x04\x88\xB2\x1E"

// BIP32 is a scheme for deriving chains of addresses from a seed value
// https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki

// Private parent key -> private child key
//
// CKDpriv((kpar, cpar), i) -> (ki, ci) computes a child extended private key from the parent extended private key:
//
// - Check whether i >= 2^31 (whether the child is a hardened key).
//     - If so (hardened child): let I = HMAC-SHA512(Key = cpar, Data = 0x00 || ser256(kpar) || ser32(i)).
//       (Note: The 0x00 pads the private key to make it 33 bytes long.)
//     - If not (normal child): let I = HMAC-SHA512(Key = cpar, Data = serP(point(kpar)) || ser32(i)).
// - Split I into two 32-byte sequences, IL and IR.
// - The returned child key ki is parse256(IL) + kpar (mod n).
// - The returned chain code ci is IR.
// - In case parse256(IL) >= n or ki = 0, the resulting key is invalid, and one should proceed with the next value for i
//   (Note: this has probability lower than 1 in 2^127.)
//
static void CKDpriv(UInt256 *k, UInt256 *c, unsigned i)
{
    unsigned char buf[sizeof(BRPubKey) + sizeof(i)];
    UInt512 I;

    if (i & BIP32_HARD) {
        buf[0] = 0;
        *(UInt256 *)&buf[1] = *k;
    }
    else
        secp256k1_point_mul(buf, NULL, *k, 1);

    *(unsigned *)&buf[sizeof(BRPubKey)] = CFSwapInt32HostToBig(i);

    HMAC(SHA512, sizeof(UInt512), c, sizeof(*c), buf, sizeof(buf), &I); // I = HMAC-SHA512(c, k|P(k) || i)

    *k = secp256k1_mod_add(*(UInt256 *)&I, *k); // k = IL + k (mod n)
    *c = *(UInt256 *)&I.u8[sizeof(UInt256)]; // c = IR

    memset(buf, 0, sizeof(buf));
    memset(&I, 0, sizeof(I));
}

// Public parent key -> public child key
//
// CKDpub((Kpar, cpar), i) -> (Ki, ci) computes a child extended public key from the parent extended public key.
// It is only defined for non-hardened child keys.
//
// - Check whether i >= 2^31 (whether the child is a hardened key).
//     - If so (hardened child): return failure
//     - If not (normal child): let I = HMAC-SHA512(Key = cpar, Data = serP(Kpar) || ser32(i)).
// - Split I into two 32-byte sequences, IL and IR.
// - The returned child key Ki is point(parse256(IL)) + Kpar.
// - The returned chain code ci is IR.
// - In case parse256(IL) >= n or Ki is the point at infinity, the resulting key is invalid, and one should proceed with
//   the next value for i.
//
static void CKDpub(BRPubKey *K, UInt256 *c, uint32_t i)
{
    if (i & BIP32_HARD)
        return; // can't derive private child key from public parent key

    unsigned char buf[sizeof(*K) + sizeof(i)];
    UInt512 I;
    BRPubKey pIL;

    *(BRPubKey *)buf = *K;
    *(unsigned *)&buf[sizeof(*K)] = CFSwapInt32HostToBig(i);

    HMAC(SHA512, sizeof(UInt512), c, sizeof(*c), buf, sizeof(buf), &I); // I = HMAC-SHA512(c, P(K) || i)

    *c = *(UInt256 *)&I.u8[sizeof(UInt256)]; // c = IR

    secp256k1_point_mul(&pIL, NULL, *(UInt256 *)&I, 1);
    secp256k1_point_add(K, &pIL, K, YES); // K = P(IL) + K

    memset(buf, 0, sizeof(buf));
    memset(&I, 0, sizeof(I));
    memset(&pIL, 0, sizeof(pIL));
}

// helper function for serializing BIP32 master public/private keys to standard export format
static NSString *serialize(uint8_t depth, uint32_t fingerprint, uint32_t child, UInt256 chain, NSData *key)
{
    NSMutableData *d = [NSMutableData secureDataWithCapacity:14 + key.length + sizeof(chain)];

    fingerprint = CFSwapInt32HostToBig(fingerprint);
    child = CFSwapInt32HostToBig(child);

    [d appendBytes:key.length < 33 ? BIP32_XPRV : BIP32_XPUB length:4];
    [d appendBytes:&depth length:1];
    [d appendBytes:&fingerprint length:sizeof(fingerprint)];
    [d appendBytes:&child length:sizeof(child)];
    [d appendBytes:&chain length:sizeof(chain)];
    if (key.length < 33)
        [d appendBytes:"\0" length:1];
    [d appendData:key];

    return [NSString base58checkWithData:d];
}

@implementation BRBIP32Sequence

#pragma mark - BRKeySequence

// master public key format is: 4 byte parent fingerprint || 32 byte chain code || 33 byte compressed public key
// the values are taken from BIP32 account m/0H
- (NSData *)masterPublicKeyFromSeed:(NSData *)seed
{
    if (!seed)
        return nil;

    NSMutableData *mpk = [NSMutableData secureData];
    UInt512 I;

    HMAC(SHA512, 64, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, &I);

    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];

    [mpk appendBytes:[BRKey keyWithSecret:secret compressed:YES].hash160.u32 length:4];

    CKDpriv(&secret, &chain, 0 | BIP32_HARD); // account 0H

    [mpk appendBytes:&chain length:sizeof(chain)];
    [mpk appendData:[BRKey keyWithSecret:secret compressed:YES].publicKey];

    return mpk;
}

- (NSData *)publicKey:(unsigned)n internal:(BOOL)internal masterPublicKey:(NSData *)masterPublicKey
{
    if (masterPublicKey.length < 4 + sizeof(UInt256) + sizeof(BRPubKey))
        return nil;

    UInt256 chain = *(const UInt256 *)((const uint8_t *)masterPublicKey.bytes + 4);
    BRPubKey pubKey = *(const BRPubKey *)((const uint8_t *)masterPublicKey.bytes + 36);

    CKDpub(&pubKey, &chain, internal ? 1 : 0); // internal or external chain
    CKDpub(&pubKey, &chain, n); // nth key in chain

    return [NSData dataWithBytes:&pubKey length:sizeof(pubKey)];
}

- (NSString *)privateKey:(unsigned)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    return seed ? [self privateKeys:@[ @(n) ] internal:internal fromSeed:seed].lastObject : nil;
}

- (NSArray *)privateKeys:(NSArray *)n internal:(BOOL)internal fromSeed:(NSData *)seed
{
    if (!seed || !n)
        return nil;
    if (n.count == 0)
        return @[];

    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n.count];
    UInt512 I;

    HMAC(SHA512, 64, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, &I);

    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    uint8_t version = BITCOIN_PRIVKEY;

#if BITCOIN_TESTNET
    version = BITCOIN_PRIVKEY_TEST;
#endif

    CKDpriv(&secret, &chain, 0 | BIP32_HARD); // account 0H
    CKDpriv(&secret, &chain, internal ? 1 : 0); // internal or external chain

    for (NSNumber *i in n) {
        NSMutableData *prvKey = [NSMutableData secureDataWithCapacity:34];
        UInt256 s = secret, c = chain;

        CKDpriv(&s, &c, i.unsignedIntValue); // nth key in chain

        [prvKey appendBytes:&version length:1];
        [prvKey appendBytes:&s length:sizeof(s)];
        [prvKey appendBytes:"\x01" length:1]; // specifies compressed pubkey format
        [a addObject:[NSString base58checkWithData:prvKey]];
    }

    return a;
}

#pragma mark - serializations

- (NSString *)serializedPrivateMasterFromSeed:(NSData *)seed
{
    if (!seed)
        return nil;

    UInt512 I;

    HMAC(SHA512, 64, BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length, &I);

    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];

    return serialize(0, 0, 0, chain, [NSData dataWithBytes:&secret length:sizeof(secret)]);
}

- (NSString *)serializedMasterPublicKey:(NSData *)masterPublicKey
{
    if (masterPublicKey.length < 36)
        return nil;

    uint32_t fingerprint = CFSwapInt32BigToHost(*(const uint32_t *)masterPublicKey.bytes);
    UInt256 chain = *(UInt256 *)((const uint8_t *)masterPublicKey.bytes + 4);
    BRPubKey pubKey = *(BRPubKey *)((const uint8_t *)masterPublicKey.bytes + 36);

    return serialize(1, fingerprint, 0 | BIP32_HARD, chain, [NSData dataWithBytes:&pubKey length:sizeof(pubKey)]);
}

@end
