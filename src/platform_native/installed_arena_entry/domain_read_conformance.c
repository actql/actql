/* Private diagnostic only: declaration metadata is the existing 64-page test,
 * not an installed supplier/profile. No backing or second provider here. */
#include "domain_read_shim.h"
#include "scoped_read.h"
extern int64_t actql_bootstrap_page_bytes(void);
extern actql_read_context *actql_bootstrap_current_read_context(void);
int actql_fixture_read_preparation_into(actql_control_reply **reply) {
    if (!reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    int64_t bytes = 64 * actql_bootstrap_page_bytes();
    moonbit_string_t source = moonbit_make_string_raw(40);
    moonbit_bytes_t recipe = moonbit_make_bytes(32, 17);
    const char *digits = "0123456789012345678901234567890123456789";
    for (int i = 0; i < 40; ++i) source[i] = (uint16_t)digits[i];
    *reply = actql_control_prepare(source, recipe, 1, bytes, 20, 8, 4, 30, 0, bytes, 65536);
    moonbit_decref(recipe);
    moonbit_decref(source);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
/* Two real managed references, only inside the original active scope. These
 * are fixture aliases, not serialized pointers or a Root/Reader substitute. */
void *actql_fixture_read_aliases(void) {
    if (!actql_bootstrap_current_read_context()) return NULL;
    moonbit_bytes_t value = moonbit_make_bytes(16, 73);
    moonbit_incref(value);
    return value;
}
void actql_fixture_read_release_alias(void *value) {
    if (value) moonbit_decref(value);
}
