#define _DARWIN_C_SOURCE
#include "component.h"
#include "owned_capacity.h"
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/provider.h>
#include <openssl/rand.h>
#include <openssl/hmac.h>
#include <dlfcn.h>
#include <stdalign.h>
#include <stdatomic.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

extern actql_read_context *actql_bootstrap_current_read_context(void);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);

typedef struct block block;
struct block {
    size_t available, requested;
    block *previous, *next_free;
};
typedef struct {
    actql_owned_capacity *lease;
    actql_read_context *context;
    pid_t process;
    size_t bytes, live_bytes, aligned_bytes, blocks, peak, failures;
    block *first, *first_free;
    unsigned char *live_starts;
    atomic_flag lock;
    unsigned initialized, closing, failed, operations, libraries, cleanup_active, base_initialized;
    OSSL_PROVIDER *default_provider;
} component_state;

/* The pointer is only an index into the original provider extent. Control,
 * allocator headers and every block live in that same non-exported extent. */
static component_state *state;
/* Test-owned counts observe real traversal in this translation unit only.
 * Normal component builds have no counters or additional exported ABI. */
#ifdef ACTQL_CRYPTO_COMPONENT_TEST_SEARCH
static size_t allocation_visits, allocation_attempts, free_visits;
#define ALLOCATION_VISIT() (allocation_visits++)
#define ALLOCATION_ATTEMPT() (allocation_attempts++)
#define FREE_VISIT() (free_visits++)
#else
#define ALLOCATION_VISIT() ((void)0)
#define ALLOCATION_ATTEMPT() ((void)0)
#define FREE_VISIT() ((void)0)
#endif
static void *original_extent;
static actql_owned_capacity *original_lease;
static actql_read_context *original_context;
static _Atomic int attempted;
/* Fixed constructor indexes are covered by the initial control envelope, not
 * an OpenSSL heap allocation. Publish the thread identity before any original
 * state access. The selected initial-Crypto component is thread-affine. */
static pthread_t original_thread;
static _Atomic int original_thread_published;
static atomic_flag close_flight = ATOMIC_FLAG_INIT;
static int original_thread_current(void) {
    return atomic_load_explicit(&original_thread_published, memory_order_acquire) &&
        pthread_equal(pthread_self(), original_thread);
}
static int cleanup_ack, heap_ack, context_ack, context_retained, hooks_installed;
static pid_t original_process;
static const size_t alignment = alignof(max_align_t);

static int current(void) {
    return original_thread_current() && state && original_process == getpid() &&
        actql_native_owned_current() == original_lease &&
        actql_bootstrap_current_read_context() == original_context;
}
static int lock_state(void) {
    return original_thread_current() && state && original_process == getpid() &&
        !atomic_flag_test_and_set_explicit(&state->lock, memory_order_acquire);
}
/* One fresh observation for this allocation callback, before touching a
 * possibly inherited state lock. The original provider checks the Read's PID,
 * active scope and lease; bind_original retained this exact immutable pair.
 * No observation is kept across callback return, unlock or another entry. */
static int lock_current_allocation_state(void) {
    return original_thread_current() && state && original_context &&
        actql_bootstrap_current_read_context() == original_context &&
        actql_native_owned_current() == original_lease &&
        !atomic_flag_test_and_set_explicit(&state->lock, memory_order_acquire);
}
static void unlock_state(void) {
    atomic_flag_clear_explicit(&state->lock, memory_order_release);
}
#include "component_arena.inc"

static int provider_origin(void) {
    Dl_info original, observed;
    if (!dladdr((void *)actql_native_owned_current, &original)) return 0;
    void *ports[] = {(void *)actql_native_owned_allocate, (void *)actql_native_owned_retire,
        (void *)actql_read_context_retain, (void *)actql_read_context_release_after_owner_ack,
        (void *)actql_bootstrap_current_read_context};
    for (size_t i = 0; i < sizeof ports / sizeof ports[0]; i++)
        if (!dladdr(ports[i], &observed) || observed.dli_fbase != original.dli_fbase) return 0;
    return 1;
}
static int bind_original(actql_read_context *original, size_t bytes, int *acquired) {
    *acquired = 0;
    size_t starts = rounded((bytes / alignment + 7) / 8);
    size_t control = rounded(sizeof(component_state));
    if (!original || bytes % alignment || !starts || starts > bytes || control > bytes - starts ||
        bytes - starts - control < header_bytes() + alignment ||
        actql_bootstrap_current_read_context() != original ||
        !actql_native_owned_current() || !provider_origin()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    int expected = 0;
    if (!atomic_compare_exchange_strong(&attempted, &expected, 1)) return ACTQL_CRYPTO_COMPONENT_INVALID;
    /* Publish custody only to the caller that consumed the original CAS,
     * before any partial context/extent/OpenSSL acquisition can fail. */
    *acquired = 1;
    original_thread = pthread_self(); original_process = getpid();
    atomic_store_explicit(&original_thread_published, 1, memory_order_release);
    original_lease = actql_native_owned_current();
    original_context = original;
    if (actql_read_context_retain(original) != 0) return ACTQL_CRYPTO_COMPONENT_FAILED;
    context_retained = 1;
    if (actql_native_owned_allocate(original_lease, bytes, alignment, &original_extent) != 0)
        return ACTQL_CRYPTO_COMPONENT_FAILED;
    state = original_extent; memset(state, 0, sizeof(*state));
    state->lease = original_lease; state->context = original; state->process = original_process;
    state->bytes = bytes; atomic_flag_clear(&state->lock);
    state->live_starts = (unsigned char *)state + control;
    state->first = (block *)(state->live_starts + starts);
    *state->first = (block){.available = bytes - control - starts - header_bytes()};
    state->first_free = state->first;
    if (CRYPTO_set_mem_functions(component_malloc, component_realloc, component_free) != 1) {
        state->failed = 1;
        return ACTQL_CRYPTO_COMPONENT_FAILED;
    }
    hooks_installed = 1;
    /* No ambient configuration, dynamic provider load or atexit cleanup: the
     * selected private instance and original lifetime remain explicit. */
    if (OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG | OPENSSL_INIT_NO_ATEXIT, NULL) != 1)
        return ACTQL_CRYPTO_COMPONENT_FAILED;
    state->base_initialized = 1;
    /* OpenSSL 3.0 can leave its static default-context carrier after failed
     * construction, then dereference its absent lock in provider loading.
     * This actual initializer reports failure without using that carrier.
     * Keep the same partial extent/context for the original close below. */
    if (OSSL_LIB_CTX_get0_global_default() == NULL)
        return ACTQL_CRYPTO_COMPONENT_FAILED;
    state->default_provider = OSSL_PROVIDER_load(NULL, "default");
    if (!state->default_provider) return ACTQL_CRYPTO_COMPONENT_FAILED;
    state->initialized = 1;
    return ACTQL_CRYPTO_COMPONENT_OK;
}
int actql_crypto_component_bind(actql_read_context *original, size_t bytes) {
    int acquired = 0;
    return bind_original(original, bytes, &acquired);
}
int actql_crypto_component_bind_current_with_custody(size_t bytes, int *acquired) {
    if (!acquired) return ACTQL_CRYPTO_COMPONENT_INVALID;
    return bind_original(actql_bootstrap_current_read_context(), bytes, acquired);
}
int actql_crypto_component_enter(actql_read_context *original) {
    if (!current() || original != original_context || !lock_state()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    int ok = state->initialized && !state->closing && !state->failed && !state->operations;
    if (ok) state->operations = 1;
    unlock_state(); return ok ? 0 : ACTQL_CRYPTO_COMPONENT_BUSY;
}
int actql_crypto_component_leave(actql_read_context *original) {
    if (!current() || original != original_context || !lock_state()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    int ok = state->operations == 1;
    if (ok) state->operations = 0;
    unlock_state(); return ok ? 0 : ACTQL_CRYPTO_COMPONENT_INVALID;
}
int actql_crypto_component_borrow_library(void) {
    if (!current() || !lock_state()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    int ok = state->initialized && !state->closing && !state->failed && state->libraries != UINT32_MAX;
    if (ok) state->libraries++;
    unlock_state(); return ok ? 0 : ACTQL_CRYPTO_COMPONENT_BUSY;
}
int actql_crypto_component_release_library(void) {
    if (!original_thread_current() || !state || original_process != getpid() || !lock_state()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    int ok = state->libraries != 0 && !state->operations;
    if (ok) state->libraries--;
    unlock_state(); return ok ? 0 : ACTQL_CRYPTO_COMPONENT_BUSY;
}
void *actql_crypto_component_symbol(const char *name) {
    if (!name || !current() || !state->libraries || state->closing || !state->operations)
        return NULL;
#define SYMBOL(value) if (!strcmp(name, #value)) return (void *)value
    SYMBOL(BIO_new_mem_buf); SYMBOL(BIO_free); SYMBOL(PEM_read_bio_PUBKEY);
    SYMBOL(PEM_read_bio_PrivateKey); SYMBOL(EVP_PKEY_free); SYMBOL(EVP_PKEY_get_base_id);
    SYMBOL(EVP_PKEY_get_raw_public_key); SYMBOL(EVP_PKEY_get_raw_private_key); SYMBOL(EVP_MD_CTX_new); SYMBOL(EVP_MD_CTX_free);
    SYMBOL(EVP_DigestVerifyInit); SYMBOL(EVP_DigestVerify); SYMBOL(EVP_sha256);
    SYMBOL(EVP_DigestInit_ex); SYMBOL(EVP_DigestUpdate); SYMBOL(EVP_DigestFinal_ex);
    SYMBOL(EVP_DigestSignInit); SYMBOL(EVP_DigestSign); SYMBOL(ERR_get_error);
    SYMBOL(ERR_error_string_n); SYMBOL(EVP_PKEY_CTX_new_id); SYMBOL(EVP_PKEY_CTX_free);
    SYMBOL(EVP_PKEY_keygen_init); SYMBOL(EVP_PKEY_keygen); SYMBOL(i2d_PrivateKey);
    SYMBOL(i2d_PUBKEY); SYMBOL(PEM_write_bio_PrivateKey); SYMBOL(PEM_write_bio_PUBKEY);
    SYMBOL(BIO_s_mem); SYMBOL(BIO_new); SYMBOL(BIO_ctrl); SYMBOL(BIO_read); SYMBOL(BIO_write);
    SYMBOL(EVP_CIPHER_CTX_new); SYMBOL(EVP_CIPHER_CTX_free); SYMBOL(EVP_CIPHER_CTX_ctrl);
    SYMBOL(EVP_aes_256_gcm); SYMBOL(EVP_EncryptInit_ex); SYMBOL(EVP_EncryptUpdate);
    SYMBOL(EVP_EncryptFinal_ex); SYMBOL(EVP_DecryptInit_ex); SYMBOL(EVP_DecryptUpdate);
    SYMBOL(EVP_DecryptFinal_ex);
    SYMBOL(RAND_bytes); SYMBOL(HMAC); SYMBOL(CRYPTO_memcmp);
#undef SYMBOL
    return NULL;
}
int actql_crypto_component_inventory(uint64_t out[12]) {
    if (!out || !lock_state()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    size_t headers = (size_t)((unsigned char *)state->first - (unsigned char *)state), free_bytes = 0;
    for (block *b = state->first; b; b = next_block(b)) {
        headers += header_bytes(); if (!b->requested) free_bytes += b->available;
    }
    uint64_t values[12] = {state->bytes,state->live_bytes,state->aligned_bytes,state->blocks,
        state->peak,headers,free_bytes,state->failures,state->libraries,state->operations,
        state->closing,state->initialized};
    memcpy(out, values, sizeof values); unlock_state(); return 0;
}
int actql_crypto_component_close(void) {
    if (!original_thread_current() || !attempted || original_process != getpid())
        return ACTQL_CRYPTO_COMPONENT_INVALID;
    /* This flight spans callbacks AND physical retirement. The allocator lock
     * remains available to the original OpenSSL cleanup callbacks. Pending or
     * failed close releases only this flight, never its original custody. */
    if (atomic_flag_test_and_set_explicit(&close_flight, memory_order_acquire))
        return ACTQL_CRYPTO_COMPONENT_BUSY;
#define CLOSE_RETURN(value) do { \
    atomic_flag_clear_explicit(&close_flight, memory_order_release); \
    return (value); \
} while (0)
    if (context_ack) CLOSE_RETURN(0);
    if (state) {
        if (!current() || !lock_state()) CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_INVALID);
        if (state->libraries || state->operations) {unlock_state(); CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_BUSY);}
        state->closing = 1; unlock_state();
        if (!hooks_installed) CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_FAILED);
        if (!cleanup_ack) {
            /* OpenSSL's hashtable retirement allocates a replacement empty
             * table before releasing the old table. These cleanup-only
             * allocations remain inside this SAME original extent; stopping
             * public operations must not deny the original cleanup its own
             * accounted old/new overlap or silently strand the old entries. */
            state->cleanup_active = 1;
            if (state->default_provider) {
                if (OSSL_PROVIDER_unload(state->default_provider) != 1) {
                    state->cleanup_active = 0;
                    CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_FAILED);
                }
                state->default_provider = NULL;
            }
            OPENSSL_thread_stop(); OPENSSL_cleanup(); state->cleanup_active = 0; cleanup_ack = 1;
        }
        if (!lock_state()) CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_BUSY);
        /* A failed, unpublished constructor has never lent a Library or an
         * operation. After successful base initialization and the original
         * thread/global stop above, its one-shot private instance cannot be
         * entered again. Retire its whole original extent, including any
         * blocks stranded by partial default-context construction. Do not
         * claim individual frees or clear allocator corruption. Published
         * instances and an unconfirmed base cleanup still require zero blocks. */
        int unpublished = state->base_initialized && !state->initialized;
        int pending = state->failed || (state->blocks != 0 && !unpublished);
        unlock_state();
        if (pending) CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_BUSY);
    }
    if (!heap_ack && original_extent) {
        if (actql_native_owned_retire(original_lease, original_extent) != 0)
            CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_FAILED);
        heap_ack = 1; state = NULL; original_extent = NULL;
    }
    if (context_retained && actql_read_context_release_after_owner_ack(original_context) != 0)
        CLOSE_RETURN(ACTQL_CRYPTO_COMPONENT_FAILED);
    context_ack = 1; CLOSE_RETURN(0);
#undef CLOSE_RETURN
}
const char *actql_crypto_component_version(void) { return OPENSSL_VERSION_TEXT; }

int actql_crypto_component_bind_current(size_t heap_bytes) {
    return actql_crypto_component_bind(actql_bootstrap_current_read_context(), heap_bytes);
}
int actql_crypto_component_enter_current(void) {
    if (!original_thread_current()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    return actql_crypto_component_enter(original_context);
}
int actql_crypto_component_leave_current(void) {
    if (!original_thread_current()) return ACTQL_CRYPTO_COMPONENT_INVALID;
    return actql_crypto_component_leave(original_context);
}
int actql_crypto_component_is_current(void) {
    return current() && state->initialized && !state->closing && !state->failed;
}
