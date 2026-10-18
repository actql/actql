#ifndef ACTQL_PRIVATE_READ_CRYPTO_SHIM_H
#define ACTQL_PRIVATE_READ_CRYPTO_SHIM_H
#include "local_host_resources_shim.h"
/* Opaque original tags from regular C emission, never layout observations.
 * Callbacks borrow inputs; replies/getters return independently owned refs.
 * The producer checks these declarations against matching regular C. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control29InstalledArenaReadCryptoReply actql_read_crypto_reply;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control29InstalledArenaCryptoComponent actql_read_crypto_component;
typedef void actql_local_crypto_library;
typedef actql_read_crypto_reply *(*actql_read_crypto_prepare_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *);
typedef actql_read_crypto_reply *(*actql_read_crypto_load_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, moonbit_string_t, int64_t, int32_t);
typedef actql_read_crypto_reply *(*actql_read_crypto_operation_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *);
typedef actql_read_crypto_reply *(*actql_read_crypto_library_operation_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *);
typedef actql_read_crypto_reply *(*actql_read_crypto_hmac_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, moonbit_bytes_t, moonbit_bytes_t);
typedef actql_read_crypto_reply *(*actql_read_crypto_verify_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, moonbit_bytes_t, moonbit_bytes_t, moonbit_bytes_t);
typedef actql_control_host *(*actql_read_crypto_host_fn)(actql_read_crypto_reply *);
typedef actql_local_host_resources *(*actql_read_crypto_pair_fn)(actql_read_crypto_reply *);
typedef actql_parent_read *(*actql_read_crypto_read_fn)(actql_read_crypto_reply *);
typedef actql_read_crypto_component *(*actql_read_crypto_component_fn)(actql_read_crypto_reply *);
typedef actql_local_crypto_library *(*actql_read_crypto_library_fn)(actql_read_crypto_reply *);
typedef int32_t (*actql_read_crypto_tag_fn)(actql_read_crypto_reply *);
typedef int32_t (*actql_read_crypto_byte_fn)(actql_read_crypto_reply *, int32_t);
typedef int32_t (*actql_read_crypto_current_fn)(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *);
void actql_native_control_register_read_crypto_roots(
    actql_read_crypto_prepare_fn, actql_read_crypto_load_fn,
    actql_read_crypto_operation_fn, actql_read_crypto_library_operation_fn,
    actql_read_crypto_operation_fn, actql_read_crypto_hmac_fn, actql_read_crypto_verify_fn,
    actql_read_crypto_host_fn, actql_read_crypto_pair_fn, actql_read_crypto_read_fn,
    actql_read_crypto_component_fn, actql_read_crypto_library_fn,
    actql_read_crypto_tag_fn, actql_read_crypto_tag_fn, actql_read_crypto_tag_fn,
    actql_read_crypto_tag_fn, actql_read_crypto_tag_fn, actql_read_crypto_tag_fn,
    actql_read_crypto_byte_fn, actql_read_crypto_current_fn);
int actql_read_crypto_prepare_into(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_reply **);
int actql_read_crypto_load_utf16_into(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, const uint16_t *, int32_t, int64_t, int32_t, actql_read_crypto_reply **);
int actql_read_crypto_operate_into(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, int32_t, actql_read_crypto_reply **);
int actql_read_crypto_hmac_into(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, const unsigned char *, int64_t, const unsigned char *, int64_t, actql_read_crypto_reply **);
int actql_read_crypto_verify_into(actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, const unsigned char *, int64_t, const unsigned char *, int64_t, const unsigned char *, int64_t, actql_read_crypto_reply **);
int actql_read_crypto_originals_into(actql_read_crypto_reply *, actql_control_host **, actql_local_host_resources **, actql_parent_read **, actql_read_crypto_component **, actql_local_crypto_library **);
int32_t actql_read_crypto_operation(actql_read_crypto_reply *);
int32_t actql_read_crypto_issue_origin(actql_read_crypto_reply *);
int32_t actql_read_crypto_issue_family(actql_read_crypto_reply *);
int32_t actql_read_crypto_close_confirmed(actql_read_crypto_reply *);
int32_t actql_read_crypto_verification(actql_read_crypto_reply *);
int actql_read_crypto_copy_output(actql_read_crypto_reply *, actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *, unsigned char *, int64_t, int64_t *);
int actql_read_crypto_drop_reply(actql_read_crypto_reply **, actql_control_host *, actql_local_host_resources *, actql_parent_read *, actql_read_crypto_component *, actql_local_crypto_library *);
int actql_read_crypto_finish_closed_data(actql_control_host **, actql_local_host_resources **, actql_parent_read **, actql_read_crypto_component **, actql_local_crypto_library **, actql_read_crypto_reply **);
int actql_read_crypto_finish_refused_prepare(actql_control_host **, actql_local_host_resources **, actql_parent_read **, actql_read_crypto_reply **);
int actql_read_crypto_finish_refused_library(actql_control_host **, actql_local_host_resources **, actql_parent_read **, actql_read_crypto_component **, actql_local_crypto_library **, actql_read_crypto_reply **);
#endif
