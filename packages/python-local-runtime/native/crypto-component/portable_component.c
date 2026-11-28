#include "portable_component.h"

#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/provider.h>
#include <pthread.h>
#include <stdalign.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/random.h>
#include <unistd.h>

typedef struct block block;
struct block {
    size_t available, requested;
    block *previous, *next_free;
};
typedef struct {
    size_t bytes, live_bytes, aligned_bytes, blocks, peak, failures;
    block *first, *first_free;
    unsigned char *live_starts;
    atomic_flag lock;
    unsigned closing, failed, cleanup_active;
    OSSL_LIB_CTX *context;
    OSSL_PROVIDER *provider;
    EVP_CIPHER *cipher;
    int hooks_installed;
    unsigned policy;
} portable_state;

static portable_state *state;
static pthread_t original_thread;
static pid_t original_process;
static atomic_int attempted;
static atomic_int owner_published;
static const size_t alignment = alignof(max_align_t);

#define ALLOCATION_VISIT() ((void)0)
#define ALLOCATION_ATTEMPT() ((void)0)
#define FREE_VISIT() ((void)0)
#define EXPORT __attribute__((visibility("default")))

static int original_thread_current(void) {
    return atomic_load_explicit(&owner_published, memory_order_acquire) &&
        original_process == getpid() && pthread_equal(original_thread, pthread_self());
}

static int lock_state(void) {
    return original_thread_current() && state &&
        !atomic_flag_test_and_set_explicit(&state->lock, memory_order_acquire);
}

static int lock_current_allocation_state(void) { return lock_state(); }
static void unlock_state(void) { atomic_flag_clear_explicit(&state->lock, memory_order_release); }

#include "component_arena.inc"

extern OSSL_provider_init_fn ossl_default_provider_init;

static int separate(const void *first, size_t first_bytes, const void *second, size_t second_bytes) {
    uintptr_t left = (uintptr_t)first, right = (uintptr_t)second;
    return left < right ? right - left >= first_bytes : left - right >= second_bytes;
}

EXPORT int actql_portable_crypto_begin(void *arena, size_t arena_bytes, unsigned policy,
                                      unsigned *custody) {
    if (!custody || (arena && !separate(arena, arena_bytes, custody, sizeof *custody)))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    *custody = 0;
    size_t required;
    switch (policy) {
    case ACTQL_PORTABLE_CRYPTO_BUILTIN_AES_256_GCM:
        required = ACTQL_PORTABLE_CRYPTO_ARENA_BYTES;
        break;
    case ACTQL_PORTABLE_CRYPTO_BUILTIN_APPROVAL:
        required = ACTQL_PORTABLE_CRYPTO_APPROVAL_ARENA_BYTES;
        break;
    default:
        return ACTQL_PORTABLE_CRYPTO_POLICY;
    }
    if (arena_bytes != required) return ACTQL_PORTABLE_CRYPTO_CAPACITY;
    if (!arena || (uintptr_t)arena % alignment) return ACTQL_PORTABLE_CRYPTO_INVALID;
    int unbound = 0;
    if (!atomic_compare_exchange_strong(&attempted, &unbound, 1))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    *custody = 1;
    original_process = getpid();
    original_thread = pthread_self();
    state = arena;
    size_t starts = rounded((arena_bytes / alignment + 7) / 8);
    size_t control = rounded(sizeof(portable_state));
    memset(state, 0, control + starts);
    state->bytes = arena_bytes;
    state->policy = policy;
    atomic_flag_clear(&state->lock);
    state->live_starts = (unsigned char *)state + control;
    state->first = (block *)(state->live_starts + starts);
    *state->first = (block){.available = arena_bytes - control - starts - header_bytes()};
    state->first_free = state->first;
    atomic_store_explicit(&owner_published, 1, memory_order_release);

    if (!CRYPTO_set_mem_functions(component_malloc, component_realloc, component_free))
        return ACTQL_PORTABLE_CRYPTO_FAILED;
    state->hooks_installed = 1;
    /* Only the hidden static image's global services are initialized here. The
     * separately created context owns all provider and cipher selections. */
    if (!OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG | OPENSSL_INIT_NO_ATEXIT, NULL))
        return ACTQL_PORTABLE_CRYPTO_FAILED;
    state->context = OSSL_LIB_CTX_new();
    if (!state->context) return ACTQL_PORTABLE_CRYPTO_FAILED;
    const char *provider = "actql_local_builtin_default";
    if (!OSSL_PROVIDER_add_builtin(state->context, provider, ossl_default_provider_init))
        return ACTQL_PORTABLE_CRYPTO_FAILED;
    state->provider = OSSL_PROVIDER_load(state->context, provider);
    if (!state->provider) return ACTQL_PORTABLE_CRYPTO_FAILED;
    EVP_CIPHER *cipher = EVP_CIPHER_fetch(state->context, "AES-256-GCM", "provider=default,fips=no");
    if (!cipher) return ACTQL_PORTABLE_CRYPTO_FAILED;
    if (EVP_CIPHER_get0_provider(cipher) != state->provider ||
        EVP_CIPHER_get_key_length(cipher) != 32 ||
        EVP_CIPHER_get_iv_length(cipher) != (int)ACTQL_PORTABLE_CRYPTO_NONCE_BYTES) {
        EVP_CIPHER_free(cipher);
        return ACTQL_PORTABLE_CRYPTO_FAILED;
    }
    state->cipher = cipher;
    return ACTQL_PORTABLE_CRYPTO_OK;
}

static int admit_buffers(void *arena, const void *key, size_t key_bytes, const void *aad,
                         size_t aad_bytes, const void *body, size_t body_bytes, void *output,
                         size_t output_bytes) {
    return original_thread_current() && arena && arena == state && state->cipher &&
        !state->closing && !state->failed && key && key_bytes == 32 && aad && aad_bytes &&
        aad_bytes <= 512 && body && body_bytes && output && output_bytes &&
        separate(arena, state->bytes, key, key_bytes) &&
        separate(arena, state->bytes, aad, aad_bytes) &&
        separate(arena, state->bytes, body, body_bytes) &&
        separate(arena, state->bytes, output, output_bytes) &&
        separate(output, output_bytes, key, key_bytes) &&
        separate(output, output_bytes, aad, aad_bytes) &&
        separate(output, output_bytes, body, body_bytes);
}

EXPORT int actql_portable_crypto_seal(void *arena, const unsigned char *key, size_t key_bytes,
                                     const unsigned char *aad, size_t aad_bytes,
                                     const unsigned char *plain, size_t plain_bytes,
                                     unsigned char *output, size_t output_bytes) {
    size_t nonce = ACTQL_PORTABLE_CRYPTO_NONCE_BYTES, tag = ACTQL_PORTABLE_CRYPTO_TAG_BYTES;
    if (plain_bytes > ACTQL_PORTABLE_CRYPTO_MAX_PLAINTEXT ||
        output_bytes != plain_bytes + nonce + tag ||
        !admit_buffers(arena, key, key_bytes, aad, aad_bytes, plain, plain_bytes, output, output_bytes))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    unsigned char scratch[ACTQL_PORTABLE_CRYPTO_TAG_BYTES];
    int expanded = 0, written = 0, final = 0;
    EVP_CIPHER_CTX *operation = EVP_CIPHER_CTX_new();
    int ok = operation && getentropy(output, nonce) == 0 &&
        EVP_EncryptInit_ex2(operation, state->cipher, key, output, NULL) &&
        EVP_EncryptUpdate(operation, NULL, &expanded, aad, (int)aad_bytes) &&
        EVP_EncryptUpdate(operation, output + nonce, &written, plain, (int)plain_bytes) &&
        written == (int)plain_bytes && EVP_EncryptFinal_ex(operation, scratch, &final) &&
        final == 0 &&
        EVP_CIPHER_CTX_ctrl(operation, EVP_CTRL_AEAD_GET_TAG, (int)tag, output + nonce + plain_bytes);
    OPENSSL_cleanse(scratch, sizeof scratch);
    EVP_CIPHER_CTX_free(operation);
    if (!ok) OPENSSL_cleanse(output, output_bytes);
    return ok ? ACTQL_PORTABLE_CRYPTO_OK : ACTQL_PORTABLE_CRYPTO_FAILED;
}

EXPORT int actql_portable_crypto_open(void *arena, const unsigned char *key, size_t key_bytes,
                                     const unsigned char *aad, size_t aad_bytes,
                                     const unsigned char *cipher, size_t cipher_bytes,
                                     unsigned char *output, size_t output_bytes) {
    size_t nonce = ACTQL_PORTABLE_CRYPTO_NONCE_BYTES, tag = ACTQL_PORTABLE_CRYPTO_TAG_BYTES;
    if (output_bytes > ACTQL_PORTABLE_CRYPTO_MAX_PLAINTEXT ||
        cipher_bytes != output_bytes + nonce + tag ||
        !admit_buffers(arena, key, key_bytes, aad, aad_bytes, cipher, cipher_bytes, output, output_bytes))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    unsigned char scratch[ACTQL_PORTABLE_CRYPTO_TAG_BYTES];
    int expanded = 0, written = 0, final = 0;
    EVP_CIPHER_CTX *operation = EVP_CIPHER_CTX_new();
    int ok = operation &&
        EVP_DecryptInit_ex2(operation, state->cipher, key, cipher, NULL) &&
        EVP_DecryptUpdate(operation, NULL, &expanded, aad, (int)aad_bytes) &&
        EVP_DecryptUpdate(operation, output, &written, cipher + nonce, (int)output_bytes) &&
        written == (int)output_bytes &&
        EVP_CIPHER_CTX_ctrl(operation, EVP_CTRL_AEAD_SET_TAG, (int)tag,
                            (void *)(cipher + nonce + output_bytes)) &&
        EVP_DecryptFinal_ex(operation, scratch, &final) && final == 0;
    OPENSSL_cleanse(scratch, sizeof scratch);
    EVP_CIPHER_CTX_free(operation);
    if (!ok) OPENSSL_cleanse(output, output_bytes);
    return ok ? ACTQL_PORTABLE_CRYPTO_OK : ACTQL_PORTABLE_CRYPTO_FAILED;
}

/* These are private physical operations. The Host chooses the registered
 * reviewer, or the distinct attestation key, on the original transaction. */
static int admit_signature_buffers(void *arena, const unsigned char *key, size_t key_bytes,
                                   const unsigned char *cid, size_t cid_bytes,
                                   const unsigned char *signature, size_t signature_bytes) {
    if (!original_thread_current() || !arena || arena != state || !state->provider ||
        state->policy != ACTQL_PORTABLE_CRYPTO_BUILTIN_APPROVAL ||
        state->closing || state->failed || !key || key_bytes != 32 ||
        !cid || cid_bytes != 71 || !signature || signature_bytes != 64 ||
        !separate(arena, state->bytes, key, key_bytes) ||
        !separate(arena, state->bytes, cid, cid_bytes) ||
        !separate(arena, state->bytes, signature, signature_bytes) ||
        !separate(signature, signature_bytes, key, key_bytes) ||
        !separate(signature, signature_bytes, cid, cid_bytes) ||
        memcmp(cid, "sha256:", 7) != 0) return 0;
    for (size_t index = 7; index < cid_bytes; ++index) {
        unsigned char c = cid[index];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return 0;
    }
    return 1;
}

EXPORT int actql_portable_crypto_verify_ed25519(void *arena, const unsigned char *public_key,
                                               size_t key_bytes, const unsigned char *cid,
                                               size_t cid_bytes, const unsigned char *signature,
                                               size_t signature_bytes) {
    if (!admit_signature_buffers(arena, public_key, key_bytes, cid, cid_bytes, signature, signature_bytes))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    const char *properties = "provider=default,fips=no";
    EVP_PKEY *key = EVP_PKEY_new_raw_public_key_ex(state->context, "ED25519", properties, public_key, key_bytes);
    EVP_MD_CTX *operation = EVP_MD_CTX_new();
    int result = -1;
    if (key && operation && EVP_PKEY_get0_provider(key) == state->provider &&
        EVP_DigestVerifyInit_ex(operation, NULL, NULL, state->context, properties, key, NULL) == 1)
        result = EVP_DigestVerify(operation, signature, signature_bytes, cid, cid_bytes);
    EVP_MD_CTX_free(operation);
    EVP_PKEY_free(key);
    if (state->failed || result < 0) return ACTQL_PORTABLE_CRYPTO_FAILED;
    return result == 1 ? ACTQL_PORTABLE_CRYPTO_OK : ACTQL_PORTABLE_CRYPTO_SIGNATURE_MISMATCH;
}

EXPORT int actql_portable_crypto_sign_attestation(void *arena, const unsigned char *private_key,
                                                 size_t key_bytes, const unsigned char *cid,
                                                 size_t cid_bytes, unsigned char *signature,
                                                 size_t signature_bytes) {
    if (!admit_signature_buffers(arena, private_key, key_bytes, cid, cid_bytes, signature, signature_bytes))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    const char *properties = "provider=default,fips=no";
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key_ex(state->context, "ED25519", properties, private_key, key_bytes);
    EVP_MD_CTX *operation = EVP_MD_CTX_new();
    size_t extent = signature_bytes;
    int ok = key && operation && EVP_PKEY_get0_provider(key) == state->provider &&
        EVP_DigestSignInit_ex(operation, NULL, NULL, state->context, properties, key, NULL) == 1 &&
        EVP_DigestSign(operation, signature, &extent, cid, cid_bytes) == 1 && extent == signature_bytes;
    EVP_MD_CTX_free(operation);
    EVP_PKEY_free(key);
    if (!ok || state->failed) {
        OPENSSL_cleanse(signature, signature_bytes);
        return ACTQL_PORTABLE_CRYPTO_FAILED;
    }
    return ACTQL_PORTABLE_CRYPTO_OK;
}

EXPORT int actql_portable_crypto_inventory(void *arena, size_t inventory[5]) {
    if (!original_thread_current() || !arena || arena != state || !inventory ||
        !separate(arena, state->bytes, inventory, 5 * sizeof *inventory))
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    inventory[0] = state->bytes;
    inventory[1] = state->peak;
    inventory[2] = state->aligned_bytes;
    inventory[3] = state->blocks;
    inventory[4] = state->failures;
    return ACTQL_PORTABLE_CRYPTO_OK;
}

EXPORT int actql_portable_crypto_close(void *arena, size_t inventory[5]) {
    if (actql_portable_crypto_inventory(arena, inventory) != ACTQL_PORTABLE_CRYPTO_OK)
        return ACTQL_PORTABLE_CRYPTO_INVALID;
    if (state->closing) return ACTQL_PORTABLE_CRYPTO_CLEANUP_PENDING;
    state->closing = state->cleanup_active = 1;
    EVP_CIPHER_free(state->cipher);
    if (state->provider && OSSL_PROVIDER_unload(state->provider) != 1)
        return ACTQL_PORTABLE_CRYPTO_CLEANUP_PENDING;
    if (state->context) {
        OPENSSL_thread_stop_ex(state->context);
        OSSL_LIB_CTX_free(state->context);
    }
    if (state->hooks_installed) OPENSSL_cleanup();
    state->cleanup_active = 0;
    actql_portable_crypto_inventory(arena, inventory);
    if (state->blocks || state->failed) return ACTQL_PORTABLE_CRYPTO_CLEANUP_PENDING;
    OPENSSL_cleanse(state, state->bytes);
    state = NULL;
    return ACTQL_PORTABLE_CRYPTO_OK;
}
