/* Private conformance only: borrow one original current provider, never link
 * another copy or acquire an anonymous backing. Fixed record is fixture control. */
#include "moonbit.h"
#include <stdint.h>
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.h"
typedef struct {
    actql_owned_capacity *owner;
    void *allocation;
    int status;
} domain_probe;
static void keep_probe(void *record) { (void)record; }
MOONBIT_FFI_EXPORT void *actql_domain_probe(int64_t bytes) {
    domain_probe *record = moonbit_make_external_object(keep_probe, sizeof(*record));
    record->owner = actql_native_owned_current();
    record->allocation = NULL;
    record->status = ACTQL_OWNED_INVALID;
    if (bytes > 0 && (uint64_t)bytes <= SIZE_MAX)
        record->status = actql_native_owned_allocate(record->owner, (size_t)bytes, 1, &record->allocation);
    if (record->status == ACTQL_OWNED_OK)
        record->status = actql_native_owned_contains_live_span(record->owner, record->allocation, (size_t)bytes);
    return record;
}
MOONBIT_FFI_EXPORT int32_t actql_domain_probe_status(domain_probe *record) { return record->status; }
MOONBIT_FFI_EXPORT int32_t actql_domain_probe_retire(domain_probe *record) {
    if (record->allocation == NULL) return ACTQL_OWNED_INVALID;
    int status = actql_native_owned_retire(record->owner, record->allocation);
    if (status == ACTQL_OWNED_OK) record->allocation = NULL;
    return status;
}
