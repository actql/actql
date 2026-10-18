/* A component fixture's owned Library, obtained from the existing Native
 * primitive. No Library layout, synthetic handle or operational supplier. */
#include "moonbit.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

extern void *actql_native_signature_load_library(moonbit_bytes_t, int32_t, int32_t);
extern bool actql_native_signature_library_ready(void *);
extern int32_t actql_native_signature_library_close(void *);

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
