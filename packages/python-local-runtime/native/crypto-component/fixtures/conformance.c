#define _DARWIN_C_SOURCE
#include "component.h"
#include "owned_capacity.h"
#include <openssl/evp.h>
#include <openssl/crypto.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>
extern int actql_read_context_create(actql_owned_capacity *, actql_read_context **);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);
extern int actql_read_context_enter(actql_read_context *);
extern int actql_read_context_leave(actql_read_context *);
extern int actql_read_context_try_close(actql_read_context **);

#define GET(type, name) type name = (type)actql_crypto_component_symbol(#name); assert(name)
typedef EVP_MD_CTX *(*md_new_fn)(void);
typedef void (*md_free_fn)(EVP_MD_CTX *);
typedef const EVP_MD *(*sha_fn)(void);
typedef int (*init_fn)(EVP_MD_CTX *, const EVP_MD *, ENGINE *);
typedef int (*update_fn)(EVP_MD_CTX *, const void *, size_t);
typedef int (*finish_fn)(EVP_MD_CTX *, unsigned char *, unsigned int *);
typedef EVP_PKEY_CTX *(*key_context_fn)(int, ENGINE *);
typedef int (*key_init_fn)(EVP_PKEY_CTX *);
typedef int (*keygen_fn)(EVP_PKEY_CTX *, EVP_PKEY **);
typedef void (*key_context_free_fn)(EVP_PKEY_CTX *);
typedef void (*key_free_fn)(EVP_PKEY *);
typedef int (*raw_key_fn)(const EVP_PKEY *, unsigned char *, size_t *);
typedef void (*memory_functions_fn)(CRYPTO_malloc_fn *, CRYPTO_realloc_fn *, CRYPTO_free_fn *);

typedef struct {
    actql_owned_capacity *lease;
    actql_read_context *context;
    atomic_int ready, go;
} competing_close;
static void *foreign_close(void *raw) {
    competing_close *value = raw;
    assert(actql_native_owned_enter(value->lease) == 0);
    assert(actql_read_context_enter(value->context) == 0);
    atomic_store(&value->ready, 1);
    while (!atomic_load(&value->go)) usleep(100);
    for (int i = 0; i < 512; i++) {
        uint64_t untouched[12] = {0};
        assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_INVALID);
        assert(actql_crypto_component_inventory(untouched) == ACTQL_CRYPTO_COMPONENT_INVALID);
        assert(actql_crypto_component_enter(value->context) == ACTQL_CRYPTO_COMPONENT_INVALID);
        for (int j = 0; j < 12; j++) assert(untouched[j] == 0);
    }
    assert(actql_read_context_leave(value->context) == 0);
    assert(actql_native_owned_leave(value->lease) == 0);
    return NULL;
}

int main(int argc, char **argv) {
    assert(argc == 3);
    const char *name = argv[1];
    void *system = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL); assert(system);
    memory_functions_fn system_memory = (memory_functions_fn)dlsym(system, "CRYPTO_get_mem_functions");
    assert(system_memory);
    CRYPTO_malloc_fn before_malloc, after_malloc; CRYPTO_realloc_fn before_realloc, after_realloc;
    CRYPTO_free_fn before_free, after_free;
    system_memory(&before_malloc, &before_realloc, &before_free);
    const unsigned char recipe[32] = {17};
    actql_owned_capacity *lease = NULL; actql_read_context *context = NULL, *foreign = NULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    assert(actql_native_owned_acquire(64 * page, 1, recipe, &lease) == 0);
    assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(lease) == 0);
    assert(actql_read_context_create(lease, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    if (!strcmp(name, "foreign-original")) {
        assert(actql_read_context_create(lease, &foreign) == 0);
        assert(actql_read_context_retain(foreign) == 0);
    }
    assert(actql_read_context_enter(context) == 0);
    if (!strcmp(name, "missing-current")) {
        assert(actql_read_context_leave(context) == 0);
        assert(actql_crypto_component_bind(context, 32 * page) == ACTQL_CRYPTO_COMPONENT_INVALID);
        assert(actql_read_context_enter(context) == 0);
    }
    if (foreign) assert(actql_crypto_component_bind(foreign, 32 * page) == ACTQL_CRYPTO_COMPONENT_INVALID);
    int bound = actql_crypto_component_bind(context,
        !strcmp(name, "initialization-exhaustion") ? 4096 : 32 * page);
    if (!strcmp(name, "initialization-exhaustion")) {
        assert(bound == ACTQL_CRYPTO_COMPONENT_FAILED);
        assert(actql_crypto_component_bind(context, 32 * page) == ACTQL_CRYPTO_COMPONENT_INVALID);
        assert(actql_crypto_component_close() == 0);
    } else {
        assert(bound == 0);
        uint64_t baseline[12] = {0}, held[12] = {0};
        assert(actql_crypto_component_inventory(baseline) == 0);
        assert(baseline[0] == 32 * page && baseline[3] > 0);
        assert(baseline[2] + baseline[5] + baseline[6] == baseline[0]);
        if (foreign) {
            assert(actql_crypto_component_enter(foreign) == ACTQL_CRYPTO_COMPONENT_INVALID);
            assert(actql_read_context_leave(context) == 0);
            assert(actql_read_context_enter(foreign) == 0);
            assert(actql_crypto_component_enter(foreign) == ACTQL_CRYPTO_COMPONENT_INVALID);
            assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_INVALID);
            assert(actql_read_context_leave(foreign) == 0);
            assert(actql_read_context_enter(context) == 0);
        }
        assert(actql_crypto_component_enter(context) == 0);
        assert(actql_crypto_component_enter(context) == ACTQL_CRYPTO_COMPONENT_BUSY);
        assert(actql_crypto_component_borrow_library() == 0);
        assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_BUSY);
        assert(actql_crypto_component_symbol("malloc") == NULL);
        GET(md_new_fn, EVP_MD_CTX_new); GET(md_free_fn, EVP_MD_CTX_free);
        GET(sha_fn, EVP_sha256); GET(init_fn, EVP_DigestInit_ex);
        GET(update_fn, EVP_DigestUpdate); GET(finish_fn, EVP_DigestFinal_ex);
        EVP_MD_CTX *md = EVP_MD_CTX_new(); assert(md);
        assert(EVP_DigestInit_ex(md, EVP_sha256(), NULL) == 1);
        assert(EVP_DigestUpdate(md, "abc", 3) == 1);
        unsigned char digest[32]; unsigned int size = 0;
        assert(EVP_DigestFinal_ex(md, digest, &size) == 1 && size == 32);
        const unsigned char expected[32] = {0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,
            0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,0xb0,0x03,0x61,0xa3,0x96,0x17,
            0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad};
        assert(!memcmp(digest, expected, sizeof expected)); EVP_MD_CTX_free(md);
        GET(key_context_fn, EVP_PKEY_CTX_new_id); GET(key_init_fn, EVP_PKEY_keygen_init);
        GET(keygen_fn, EVP_PKEY_keygen); GET(key_context_free_fn, EVP_PKEY_CTX_free);
        GET(key_free_fn, EVP_PKEY_free); GET(raw_key_fn, EVP_PKEY_get_raw_private_key);
        GET(raw_key_fn, EVP_PKEY_get_raw_public_key);
        EVP_PKEY_CTX *key_context = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, NULL); assert(key_context);
        assert(EVP_PKEY_keygen_init(key_context) == 1);
        EVP_PKEY *key = NULL;
        int generated = EVP_PKEY_keygen(key_context, &key);
        if (generated != 1 || !key) {
            uint64_t observed[12] = {0};
            assert(actql_crypto_component_inventory(observed) == 0);
            fprintf(stderr, "keygen=%d heap=%llu requested=%llu aligned=%llu blocks=%llu peak=%llu headers=%llu free=%llu failures=%llu\n",
                generated, (unsigned long long)observed[0], (unsigned long long)observed[1],
                (unsigned long long)observed[2], (unsigned long long)observed[3],
                (unsigned long long)observed[4], (unsigned long long)observed[5],
                (unsigned long long)observed[6], (unsigned long long)observed[7]);
            typedef unsigned long (*error_fn)(void);
            typedef void (*error_text_fn)(unsigned long, char *, size_t);
            error_fn error = (error_fn)actql_crypto_component_symbol("ERR_get_error");
            error_text_fn text = (error_text_fn)actql_crypto_component_symbol("ERR_error_string_n");
            unsigned long code;
            while ((code = error()) != 0) {char message[256]; text(code, message, sizeof message); fprintf(stderr, "%s\n", message);}
        }
        assert(generated == 1 && key);
        /* Use the existing signature key-generation path, not the different
         * generic i2d_PrivateKey serialization choice. RFC 8410 has fixed
         * PKCS#8/SPKI prefixes followed by the exact 32-byte key material. */
        unsigned char private_der[48] = {0x30,0x2e,0x02,0x01,0x00,0x30,0x05,0x06,
            0x03,0x2b,0x65,0x70,0x04,0x22,0x04,0x20};
        unsigned char public_der[44] = {0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00};
        size_t private_size = 32, public_size = 32;
        assert(EVP_PKEY_get_raw_private_key(key, private_der + 16, &private_size) == 1 && private_size == 32);
        assert(EVP_PKEY_get_raw_public_key(key, public_der + 12, &public_size) == 1 && public_size == 32);
        memset(private_der, 0, sizeof private_der);
        assert(actql_crypto_component_inventory(held) == 0 && held[3] > baseline[3]);
        EVP_PKEY_free(key); EVP_PKEY_CTX_free(key_context);
        if (!strcmp(name, "heap-exhaustion-realloc")) {
            typedef const BIO_METHOD *(*bio_method_fn)(void);
            typedef BIO *(*bio_new_fn)(const BIO_METHOD *);
            typedef int (*bio_write_fn)(BIO *, const void *, int);
            typedef int (*bio_free_fn)(BIO *);
            GET(bio_method_fn, BIO_s_mem); GET(bio_new_fn, BIO_new);
            GET(bio_write_fn, BIO_write); GET(bio_free_fn, BIO_free);
            BIO *bio = BIO_new(BIO_s_mem()); assert(bio);
            char bytes[32] = {17};
            assert(BIO_write(bio, bytes, sizeof bytes) == sizeof bytes);
            /* A request larger than the entire extent must fail without
             * losing the original BIO buffer or acquiring another extent. */
            char large[524288] = {0};
            assert(BIO_write(bio, large, sizeof large) <= 0);
            uint64_t bounded[12] = {0};
            assert(actql_crypto_component_inventory(bounded) == 0);
            assert(bounded[0] == baseline[0] && bounded[7] > baseline[7]);
            assert(bounded[2] + bounded[5] + bounded[6] == bounded[0]);
            assert(BIO_write(bio, bytes, sizeof bytes) == sizeof bytes);
            assert(BIO_free(bio) == 1);
        }
        assert(actql_crypto_component_leave(context) == 0);
        assert(actql_crypto_component_release_library() == 0);
        pthread_t competitor;
        competing_close competing = {.lease = lease, .context = context};
        int has_competitor = !strcmp(name, "foreign-thread-close");
        if (has_competitor) {
            atomic_init(&competing.ready, 0); atomic_init(&competing.go, 0);
            assert(pthread_create(&competitor, NULL, foreign_close, &competing) == 0);
            while (!atomic_load(&competing.ready)) usleep(100);
            atomic_store(&competing.go, 1);
        }
        int close_status = actql_crypto_component_close();
        if (has_competitor) assert(pthread_join(competitor, NULL) == 0);
        if (close_status != 0) {
            uint64_t pending[12] = {0};
            if (actql_crypto_component_inventory(pending) == 0)
                fprintf(stderr, "close=%d live=%llu aligned=%llu blocks=%llu headers=%llu free=%llu fail=%llu\n",
                    close_status, (unsigned long long)pending[1], (unsigned long long)pending[2],
                    (unsigned long long)pending[3], (unsigned long long)pending[5],
                    (unsigned long long)pending[6], (unsigned long long)pending[7]);
        }
        assert(close_status == 0);
        assert(actql_crypto_component_bind(context, 32 * page) == ACTQL_CRYPTO_COMPONENT_INVALID);
    }
    system_memory(&after_malloc, &after_realloc, &after_free);
    assert(before_malloc == after_malloc && before_realloc == after_realloc && before_free == after_free);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(lease) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == 0 && !context);
    if (foreign) {
        assert(actql_read_context_release_after_owner_ack(foreign) == 0);
        assert(actql_read_context_try_close(&foreign) == 0 && !foreign);
    }
    assert(actql_native_owned_try_close(&lease) == 0 && !lease);
    assert(dlclose(system) == 0);
    printf("{\"case\":\"%s\",\"pass\":true,\"private_host_pages\":64,\"normal_funding\":false}\n", name);
}
