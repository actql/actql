/* A component fixture's owned Library, obtained from the existing Native
 * primitive. No Library layout, synthetic handle or operational supplier. */
#include "moonbit.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

extern void *actql_native_signature_load_library(moonbit_bytes_t, int32_t, int32_t);
extern bool actql_native_signature_library_ready(void *);
extern int32_t actql_native_signature_library_close(void *);
extern void *actql_native_signature_sha256_new(void *);
extern bool actql_native_signature_sha256_ready(void *);
extern bool actql_native_signature_sha256_update(void *, moonbit_bytes_t, int32_t);
extern moonbit_bytes_t actql_native_signature_sha256_finish(void *);
extern bool actql_native_signature_sha256_close(void *);

/* Called inside the original Read phase. All returned managed values and the
 * original hasher are released before leaving; the outer context close must
 * still detect any allocation the primitive itself loses. */
int actql_fixture_adoption_crypto_sha256(void *library) {
    static const unsigned char expected[32] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };
    void *hash = actql_native_signature_sha256_new(library);
    bool ready = actql_native_signature_sha256_ready(hash);
    moonbit_bytes_t input = moonbit_make_bytes(3, 0);
    memcpy(input, "abc", 3);
    bool updated = actql_native_signature_sha256_update(hash, input, 3);
    moonbit_decref(input);
    moonbit_bytes_t digest = actql_native_signature_sha256_finish(hash);
    bool exact = Moonbit_array_length(digest) == 32 &&
        memcmp(digest, expected, sizeof(expected)) == 0;
    moonbit_decref(digest);
    moonbit_bytes_t again = actql_native_signature_sha256_finish(hash);
    bool refused = Moonbit_array_length(again) == 0;
    moonbit_decref(again);
    moonbit_bytes_t absent = actql_native_signature_sha256_finish(NULL);
    bool invalid = Moonbit_array_length(absent) == 0;
    moonbit_decref(absent);
    bool closed = actql_native_signature_sha256_close(hash);
    moonbit_decref(hash);
    return ready && updated && exact && refused && invalid && closed ? 0 : -1;
}

int actql_fixture_adoption_crypto_into(const char *path, int32_t length, void **slot) {
    if (!path || length <= 0 || length > 4096 || !slot || *slot) return -1;
    moonbit_bytes_t bytes = moonbit_make_bytes(length, 0);
    memcpy(bytes, path, (size_t)length);
    *slot = actql_native_signature_load_library(bytes, length, 128);
    moonbit_decref(bytes);
    return *slot && actql_native_signature_library_ready(*slot) ? 0 : -2;
}

int actql_fixture_adoption_crypto_close(void **slot) {
    if (!slot) return -1;
    if (!*slot) return 0;
    int32_t status = actql_native_signature_library_close(*slot);
    if (status != 0) return status;
    void *original = *slot;
    *slot = NULL;
    moonbit_decref(original);
    return 0;
}
