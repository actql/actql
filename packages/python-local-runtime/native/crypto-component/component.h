#ifndef ACTQL_PRIVATE_CRYPTO_COMPONENT_H
#define ACTQL_PRIVATE_CRYPTO_COMPONENT_H
#include <stddef.h>
#include <stdint.h>
typedef struct actql_read_context actql_read_context;
enum actql_crypto_component_status {
    ACTQL_CRYPTO_COMPONENT_OK = 0,
    ACTQL_CRYPTO_COMPONENT_INVALID = -1,
    ACTQL_CRYPTO_COMPONENT_BUSY = -2,
    ACTQL_CRYPTO_COMPONENT_FAILED = -3
};
/* The caller supplies its already-current original Domain. This is not a
 * resource issuer, a signer selection or an installed numerical profile. */
int actql_crypto_component_bind(actql_read_context *original, size_t heap_bytes);
int actql_crypto_component_enter(actql_read_context *original);
int actql_crypto_component_leave(actql_read_context *original);
/* The existing Library must retain this borrow until all EVP/BIO/key/hasher
 * users finish. Only the closed selected symbol table is exposed. */
int actql_crypto_component_borrow_library(void);
int actql_crypto_component_release_library(void);
void *actql_crypto_component_symbol(const char *name);
/* Exact physical census, not quota or a cleanup ACK: heap, live requested,
 * live aligned payload, live blocks, peak aligned payload, headers, free bytes,
 * failures, Library borrows, active operation, closing and initialized. */
int actql_crypto_component_inventory(uint64_t out[12]);
/* One-shot instance cleanup. Failed retirement retains its original extent and
 * user. A cleaned instance cannot be rebound or reinitialized. */
int actql_crypto_component_close(void);
const char *actql_crypto_component_version(void);
#endif
