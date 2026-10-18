/* Test-only transport of an actual Root under the original Read scope.
 * This helper supplies no provider, allocator, capacity or cleanup authority. */
#include "local_host_resources_shim.h"
#include <string.h>
extern void *actql_native_filesystem_acquire_current_root(moonbit_bytes_t, int32_t, int32_t);
extern int32_t actql_native_filesystem_acquisition_status(void *);
extern int32_t actql_native_filesystem_acquisition_has_original(void *);
extern void *actql_native_filesystem_acquisition_root(void *);
extern int32_t actql_native_filesystem_root_close_dispatch(void *);

int actql_fixture_root_into(const unsigned char *path, int32_t bytes,
    void **acquisition, void **root) {
    if (!path || bytes <= 0 || bytes > 4096 || !acquisition || !root ||
        acquisition == root || *acquisition || *root || memchr(path, 0, (size_t)bytes))
        return ACTQL_CONTROL_INVALID_SLOT;
    moonbit_bytes_t input = moonbit_make_bytes(bytes, 0);
    memcpy(input, path, (size_t)bytes);
    *acquisition = actql_native_filesystem_acquire_current_root(input, bytes, 128);
    moonbit_decref(input);
    if (!*acquisition || actql_native_filesystem_acquisition_status(*acquisition) != 0 ||
        actql_native_filesystem_acquisition_has_original(*acquisition) != 1)
        return ACTQL_CONTROL_UNAVAILABLE;
    *root = actql_native_filesystem_acquisition_root(*acquisition);
    if (!*root) return ACTQL_CONTROL_UNAVAILABLE;
    /* Publish the owned Root before retiring its acquisition DATA. */
    void *captured = *acquisition; *acquisition = NULL; moonbit_decref(captured);
    return ACTQL_CONTROL_OK;
}

int actql_fixture_root_close(void *root) {
    return root ? actql_native_filesystem_root_close_dispatch(root)
                : ACTQL_CONTROL_INVALID_SLOT;
}

int actql_fixture_drop_root_alias(void **root) {
    if (!root || !*root) return ACTQL_CONTROL_INVALID_SLOT;
    /* DATA-only release, separately from the observed Root descriptor ACK. */
    void *original = *root; *root = NULL; moonbit_decref(original);
    return ACTQL_CONTROL_OK;
}
