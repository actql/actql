/* Private diagnostic only: declaration metadata is the existing accepted D Source0df87e9d6 8192-page diagnostic,
 * not an installed supplier/profile. No backing or second provider here. */
#include "domain_read_shim.h"
#include "scoped_read.h"
extern int64_t actql_bootstrap_page_bytes(void);
extern actql_read_context *actql_bootstrap_current_read_context(void);
int actql_fixture_runtime_preparation_into(actql_control_reply **reply) {
    if (!reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    int64_t bytes = 8192 * actql_bootstrap_page_bytes();
    moonbit_string_t source = moonbit_make_string_raw(40);
    moonbit_bytes_t recipe = moonbit_make_bytes(32, 17);
    const char *digits = "0123456789012345678901234567890123456789";
    for (int i = 0; i < 40; ++i) source[i] = (uint16_t)digits[i];
    *reply = actql_control_prepare(source, recipe, 1, bytes, 20, 8, 4, 30, 0, bytes, 65536);
    moonbit_decref(recipe);
    moonbit_decref(source);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
