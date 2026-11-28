#ifndef ACTQL_PORTABLE_CRYPTO_COMPONENT_H
#define ACTQL_PORTABLE_CRYPTO_COMPONENT_H

#include <stddef.h>

#define ACTQL_PORTABLE_CRYPTO_ARENA_BYTES ((size_t)524288)
#define ACTQL_PORTABLE_CRYPTO_APPROVAL_ARENA_BYTES ((size_t)786432)
#define ACTQL_PORTABLE_CRYPTO_MAX_PLAINTEXT ((size_t)1048576)
#define ACTQL_PORTABLE_CRYPTO_NONCE_BYTES ((size_t)12)
#define ACTQL_PORTABLE_CRYPTO_TAG_BYTES ((size_t)16)

enum ActqlPortableCryptoStatus {
    ACTQL_PORTABLE_CRYPTO_OK,
    ACTQL_PORTABLE_CRYPTO_INVALID,
    ACTQL_PORTABLE_CRYPTO_POLICY,
    ACTQL_PORTABLE_CRYPTO_FAILED,
    ACTQL_PORTABLE_CRYPTO_CAPACITY,
    ACTQL_PORTABLE_CRYPTO_CLEANUP_PENDING,
    ACTQL_PORTABLE_CRYPTO_SIGNATURE_MISMATCH
};

enum ActqlPortableCryptoPolicy {
    ACTQL_PORTABLE_CRYPTO_BUILTIN_AES_256_GCM = 1,
    /* Value 2 remains refused for the existing FIPS-required profile. */
    ACTQL_PORTABLE_CRYPTO_BUILTIN_APPROVAL = 3
};

/* A trusted Host supplies the already-funded, aligned original arena. Only
 * the caller that receives custody may close it. Each loaded image is bound
 * once to one original process/thread. The artifact does not allocate an arena. */
int actql_portable_crypto_begin(void *arena, size_t arena_bytes, unsigned policy,
                               unsigned *custody);

/* These operations borrow disjoint buffers from the already-funded original.
 * Seal writes nonce, ciphertext and tag. Open authenticates before its output
 * is returned. The caller supplies exact lengths and owns all byte backing. */
int actql_portable_crypto_seal(void *arena, const unsigned char *key, size_t key_bytes,
                              const unsigned char *aad, size_t aad_bytes,
                              const unsigned char *plain, size_t plain_bytes,
                              unsigned char *output, size_t output_bytes);
int actql_portable_crypto_open(void *arena, const unsigned char *key, size_t key_bytes,
                              const unsigned char *aad, size_t aad_bytes,
                              const unsigned char *cipher, size_t cipher_bytes,
                              unsigned char *output, size_t output_bytes);

/* The existing private component verifies a reviewer proof or signs a Host
 * attestation over one already-authorized canonical CID. Public and private
 * inputs remain in the caller's separate admitted and funded custody. */
int actql_portable_crypto_verify_ed25519(void *arena, const unsigned char *public_key,
                                        size_t key_bytes, const unsigned char *cid, size_t cid_bytes,
                                        const unsigned char *signature, size_t signature_bytes);
int actql_portable_crypto_sign_attestation(void *arena, const unsigned char *private_key,
                                          size_t key_bytes, const unsigned char *cid, size_t cid_bytes,
                                          unsigned char *signature, size_t signature_bytes);

/* Observe reserved bytes, peak aligned payload, current aligned payload,
 * live blocks and failures. Only successful close returns the arena. */
int actql_portable_crypto_inventory(void *arena, size_t inventory[5]);
int actql_portable_crypto_close(void *arena, size_t inventory[5]);

#endif
