#define _DARWIN_C_SOURCE
#include "moonbit.h"
#include "owned_capacity.h"
#include <assert.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct actql_read_context actql_read_context;
extern int actql_read_context_create(actql_owned_capacity *, actql_read_context **);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);
extern int actql_read_context_enter(actql_read_context *);
extern int actql_read_context_leave(actql_read_context *);
extern int actql_read_context_try_close(actql_read_context **);
extern void *actql_native_crypto_component_load(moonbit_bytes_t, int32_t, int64_t, int32_t);
extern bool actql_native_crypto_component_ready(void *);
extern int32_t actql_native_crypto_component_close(void *);
extern void *actql_native_crypto_component_library(void *);
extern bool actql_native_signature_library_ready(void *);
extern int32_t actql_native_signature_library_close(void *);
extern void *actql_native_signature_sha256_new(void *);
extern bool actql_native_signature_sha256_update(void *, moonbit_bytes_t, int32_t);
extern moonbit_bytes_t actql_native_signature_sha256_finish(void *);
extern bool actql_native_signature_sha256_close(void *);
extern moonbit_bytes_t actql_native_signature_random_bytes(void *, int32_t);
extern moonbit_bytes_t actql_native_signature_hmac_sha256(void *, moonbit_bytes_t, int32_t, moonbit_bytes_t, int32_t);
extern int32_t actql_native_signature_equal_tag(void *, moonbit_bytes_t, moonbit_bytes_t);
extern int32_t actql_native_signature_generate_ed25519(void *, moonbit_bytes_t, int32_t, moonbit_bytes_t, int32_t);
extern moonbit_bytes_t actql_native_private_evidence_cipher(void *, moonbit_bytes_t, int32_t, moonbit_bytes_t, int32_t, moonbit_bytes_t, int32_t, int32_t);

static moonbit_bytes_t bytes(const char *text) {
    size_t length = strlen(text); moonbit_bytes_t value = moonbit_make_bytes_raw((int32_t)length);
    memcpy(value, text, length); return value;
}
typedef struct {
    actql_owned_capacity *lease; actql_read_context *context;
    void *component, *library, *hash;
    atomic_int ready, go;
} original_call;
static void *foreign(void *raw) {
    original_call *call = raw;
    assert(actql_native_owned_enter(call->lease) == 0);
    assert(actql_read_context_enter(call->context) == 0);
    atomic_store(&call->ready, 1);
    while (!atomic_load(&call->go)) usleep(100);
    for (int i = 0; i < 512; i++) {
        assert(!actql_native_crypto_component_ready(call->component));
        assert(!actql_native_signature_library_ready(call->library));
        assert(!actql_native_signature_sha256_update(call->hash, NULL, 0));
        assert(!actql_native_signature_sha256_close(call->hash));
        assert(actql_native_signature_library_close(call->library) == 2);
        assert(actql_native_crypto_component_close(call->component) == 2);
    }
    assert(actql_read_context_leave(call->context) == 0);
    assert(actql_native_owned_leave(call->lease) == 0); return NULL;
}
int main(int argc, char **argv) {
    assert(argc == 3); size_t page = (size_t)sysconf(_SC_PAGESIZE);
    const unsigned char recipe[32] = {19};
    actql_owned_capacity *lease = NULL; actql_read_context *context = NULL;
    assert(actql_native_owned_acquire(64 * page, 1, recipe, &lease) == 0);
    assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
    assert(actql_native_owned_enter(lease) == 0);
    assert(actql_read_context_create(lease, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    assert(actql_read_context_enter(context) == 0);
    moonbit_bytes_t path = bytes(argv[1]);
    void *component = actql_native_crypto_component_load(path, (int32_t)strlen(argv[1]),
        !strcmp(argv[2], "partial") ? 4096 : (int64_t)(32 * page), 256);
    if (!strcmp(argv[2], "duplicate")) {
        assert(actql_native_crypto_component_ready(component));
        void *refused = actql_native_crypto_component_load(path, (int32_t)strlen(argv[1]), (int64_t)(32 * page), 256);
        assert(!actql_native_crypto_component_ready(refused));
        assert(actql_native_crypto_component_close(refused) == 0);
        assert(actql_native_crypto_component_ready(component));
        moonbit_decref(refused);
    }
    moonbit_decref(path);
    if (!strcmp(argv[2], "partial")) {
        assert(!actql_native_crypto_component_ready(component));
        assert(actql_native_crypto_component_close(component) == 0);
    } else {
        assert(actql_native_crypto_component_ready(component));
        void *outer = actql_native_crypto_component_library(component);
        void *inner = actql_native_crypto_component_library(component);
        assert(actql_native_signature_library_ready(outer));
        assert(actql_native_signature_library_ready(inner));
        assert(actql_native_crypto_component_close(component) == 1);
        void *hash = actql_native_signature_sha256_new(outer);
        moonbit_bytes_t text = bytes("abc");
        assert(actql_native_signature_sha256_update(hash, text, 3));
        moonbit_bytes_t digest = actql_native_signature_sha256_finish(hash);
        const unsigned char expected[32] = {0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad};
        assert(Moonbit_array_length(digest) == 32 && !memcmp(digest, expected, 32));
        moonbit_bytes_t random = actql_native_signature_random_bytes(inner, 32);
        assert(Moonbit_array_length(random) == 32);
        moonbit_bytes_t key = bytes("key");
        moonbit_bytes_t tag = actql_native_signature_hmac_sha256(inner, key, 3, text, 3);
        assert(Moonbit_array_length(tag) == 32);
        const unsigned char hmac[32] = {0x9c,0x19,0x6e,0x32,0xdc,0x01,0x75,0xf8,0x6f,0x4b,0x1c,0xb8,0x92,0x89,0xd6,0x61,0x9d,0xe6,0xbe,0xe6,0x99,0xe4,0xc3,0x78,0xe6,0x83,0x09,0xed,0x97,0xa1,0xa6,0xab};
        assert(!memcmp(tag, hmac, 32));
        assert(actql_native_signature_equal_tag(inner, tag, tag) == 0);
        moonbit_bytes_t encrypted = actql_native_private_evidence_cipher(inner, random, 32, text, 3, text, 3, 1);
        assert(Moonbit_array_length(encrypted) == 32 && encrypted[0] == 0);
        moonbit_bytes_t decrypted = actql_native_private_evidence_cipher(inner, random, 32, text, 3, encrypted + 1, 31, 0);
        assert(Moonbit_array_length(decrypted) == 4 && decrypted[0] == 0 && !memcmp(decrypted + 1, "abc", 3));
        moonbit_bytes_t private_key = moonbit_make_bytes_raw(48), public_key = moonbit_make_bytes_raw(44);
        assert(actql_native_signature_generate_ed25519(outer, private_key, 48, public_key, 44) == 0);
        memset(private_key, 0, 48);
        moonbit_decref(private_key); moonbit_decref(public_key);
        moonbit_decref(text); moonbit_decref(key); moonbit_decref(tag); moonbit_decref(random);
        moonbit_decref(encrypted); moonbit_decref(decrypted); moonbit_decref(digest); moonbit_decref(hash);
        hash = actql_native_signature_sha256_new(outer);
        assert(actql_native_signature_library_close(outer) == 1);
        assert(actql_native_signature_library_close(inner) == 0);
        assert(actql_native_crypto_component_close(component) == 1);
        original_call call = {.lease=lease, .context=context, .component=component, .library=outer, .hash=hash};
        pthread_t thread; assert(pthread_create(&thread, NULL, foreign, &call) == 0);
        while (!atomic_load(&call.ready)) usleep(100);
        atomic_store(&call.go, 1);
        assert(actql_native_signature_sha256_close(hash));
        assert(actql_native_signature_library_close(outer) == 0);
        if (!strcmp(argv[2], "duplicate")) {
            moonbit_bytes_t same_path = bytes(argv[1]);
            void *refused = actql_native_crypto_component_load(same_path, (int32_t)strlen(argv[1]), (int64_t)(32 * page), 256);
            moonbit_decref(same_path);
            assert(!actql_native_crypto_component_ready(refused));
            assert(actql_native_crypto_component_close(refused) == 0);
            assert(actql_native_crypto_component_ready(component));
            moonbit_decref(refused);
        }
        assert(actql_native_crypto_component_close(component) == 0);
        assert(pthread_join(thread, NULL) == 0);
        assert(!actql_native_crypto_component_ready(component));
        assert(!actql_native_signature_library_ready(outer));
        assert(!actql_native_signature_library_ready(inner));
        assert(actql_native_crypto_component_close(component) == 0);
        moonbit_decref(hash); moonbit_decref(inner); moonbit_decref(outer);
    }
    moonbit_decref(component);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == 0 && !context);
    assert(actql_native_owned_leave(lease) == 0);
    assert(actql_native_owned_try_close(&lease) == 0 && !lease);
    printf("{\"case\":\"%s\",\"pass\":true,\"typed_library\":true,\"normal_funding\":false}\n", argv[2]);
}
