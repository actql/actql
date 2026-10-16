#ifndef ACTQL_PRIVATE_PACKAGED_PRODUCT_SHIM_H
#define ACTQL_PRIVATE_PACKAGED_PRODUCT_SHIM_H
#include "packaged_runtime_shim.h"

/* Actual regular C Source0ed5bd09ce0efb805d0244753708cc5586a1d5e4,
 * SHA256 e5cadc156410b12feb7527494e606a9f499f26b7c09cea3d22ff0fa71b5ac589.
 * Managed arguments are borrowed; reply and original getters return owned
 * references. Never inspect generated fields or infer authority from metadata. */
typedef struct _M0TP45actql5actql16platform__native12client__host31NativeLocalPackagedProductReply actql_packaged_product_reply;
typedef actql_packaged_product_reply *(*actql_product_observe_fn)(
    actql_packaged_runtime *, moonbit_string_t, moonbit_string_t, moonbit_string_t, int32_t);
typedef actql_packaged_product_reply *(*actql_product_identity_fn)(actql_packaged_runtime *);
typedef actql_control_host *(*actql_product_host_fn)(actql_packaged_product_reply *);
typedef actql_parent_read *(*actql_product_read_fn)(actql_packaged_product_reply *);
typedef actql_packaged_runtime *(*actql_product_runtime_fn)(actql_packaged_product_reply *);
typedef int32_t (*actql_product_tag_fn)(actql_packaged_product_reply *);
typedef int32_t (*actql_product_unit_fn)(actql_packaged_product_reply *, int32_t);
void actql_native_control_register_packaged_product_roots(
    actql_product_observe_fn, actql_product_identity_fn,
    actql_product_host_fn, actql_product_read_fn, actql_product_runtime_fn,
    actql_product_tag_fn, actql_product_tag_fn, actql_product_tag_fn, actql_product_unit_fn);

int actql_packaged_product_observe_utf16_into(actql_packaged_runtime *,
    const uint16_t *, int32_t, const uint16_t *, int32_t,
    const uint16_t *, int32_t, int32_t, actql_packaged_product_reply **);
int actql_packaged_product_identity_into(actql_packaged_runtime *, actql_packaged_product_reply **);
/* Local nominal data comparison, not current physical/adoption/permission ACK. */
int actql_packaged_product_validate_originals(actql_packaged_product_reply *,
    actql_control_host *, actql_parent_read *, actql_packaged_runtime *);
int32_t actql_packaged_product_operation(actql_packaged_product_reply *);
int32_t actql_packaged_product_issue_family(actql_packaged_product_reply *);
int32_t actql_packaged_product_metadata_units(actql_packaged_product_reply *);
int32_t actql_packaged_product_metadata_unit_at(actql_packaged_product_reply *, int32_t);
int actql_packaged_product_drop_reply(actql_packaged_product_reply **,
    actql_control_host *, actql_parent_read *, actql_packaged_runtime *);
#endif
