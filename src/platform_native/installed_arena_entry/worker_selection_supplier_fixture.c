/* Dependent fixture caller only. Link the actual original component; never
 * compile another Core, provider, TLS, allocator or Host implementation here. */
#include "control_shim.h"
extern int64_t actql_bootstrap_page_bytes(void);
int actql_fixture_worker_prepare_into(actql_control_reply **slot) {
    if (!slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    moonbit_string_t source = moonbit_make_string_raw(40);
    moonbit_bytes_t recipe = moonbit_make_bytes(32, 17);
    const char *digits = "0123456789012345678901234567890123456789";
    for (int i = 0; i < 40; ++i) source[i] = (uint16_t)digits[i];
    int64_t bytes = 64 * actql_bootstrap_page_bytes();
    *slot = actql_control_prepare(source, recipe, 1, bytes, 20, 8, 4, 30, 0, bytes, 65536);
    moonbit_decref(source);
    moonbit_decref(recipe);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
