#include "local_journal_shim_impl.h"

/* The Runtime owns the observed members. Only borrow its nominal record here;
 * do not read MoonBit layout or introduce a member-to-Runtime retention cycle. */
extern int32_t actql_native_filesystem_bind_component_runtime(void *, const void *);
int32_t actql_native_client_bind_component_runtime(void *runtime, void *member) {
  return actql_native_filesystem_bind_component_runtime(member, runtime);
}
