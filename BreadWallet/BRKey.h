//
//  BRKey.h
//  BreadWallet
//
//  Created by Aaron Voisine on 5/22/13.
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

#import <Foundation/Foundation.h>

typedef struct _BRPubKey { uint8_t u8[33]; } BRPubKey;

#define brpubkey_obj(o) [NSValue value:&(o).form withObjCType:@encode(BRPubKey)]

typedef union _UInt256 UInt256;
typedef union _UInt160 UInt160;

UInt256 secp256k1_mod_add(UInt256 a, UInt256 b);  // add 256bit big endian ints (mod secp256k1 order)
UInt256 secp256k1_mod_mul(UInt256 a, UInt256 b);  // multiply 256bit big endian ints (mod secp256k1 order)
int secp256k1_point_add(void *r, const void *a, const void *b, int compressed);  // add secp256k1 ec-points
int secp256k1_point_mul(void *r, const void *p, UInt256 i,
                        int compressed);  // multiply ec-point by 256bit big endian int

@interface BRKey : NSObject

@property(nonatomic, readonly) NSString *privateKey;
@property(nonatomic, readonly) NSData *publicKey;
@property(nonatomic, readonly) NSString *address;
@property(nonatomic, readonly) UInt160 hash160;

+ (instancetype)keyWithPrivateKey:(NSString *)privateKey;
+ (instancetype)keyWithSecret:(UInt256)secret compressed:(BOOL)compressed;
+ (instancetype)keyWithPublicKey:(NSData *)publicKey;

- (instancetype)initWithPrivateKey:(NSString *)privateKey;
- (instancetype)initWithSecret:(UInt256)secret compressed:(BOOL)compressed;
- (instancetype)initWithPublicKey:(NSData *)publicKey;

- (NSData *)sign:(UInt256)md;
- (BOOL)verify:(UInt256)md signature:(NSData *)sig;

@end
