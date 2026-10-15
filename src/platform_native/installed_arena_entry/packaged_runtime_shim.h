#ifndef ACTQL_PRIVATE_PACKAGED_RUNTIME_SHIM_H
#define ACTQL_PRIVATE_PACKAGED_RUNTIME_SHIM_H
#include "original_read_shim.h"

/* Actual regular C at Source9f1a948d31b0f31e9965c80dfa99504819636955,
 * SHA256 7c0a1419368ffbe1d0ce75128ed5860879f719579126e5b3838a9b365b1beb0d.
 * Inputs are borrowed; reply and nullable getters return owned references.
 * Opaque tags only: never inspect generated fields or infer final retirement. */
typedef struct _M0TP45actql5actql16platform__native12client__host26NativeLocalPackagedRuntime actql_packaged_runtime;
typedef struct _M0TP45actql5actql16platform__native12client__host31NativeLocalPackagedRuntimeReply actql_packaged_runtime_reply;
typedef actql_packaged_runtime_reply *(*actql_runtime_capture_fn)(
    actql_control_host *, actql_parent_read *, moonbit_string_t,
    moonbit_string_t, moonbit_string_t, moonbit_string_t, int32_t);
typedef actql_packaged_runtime_reply *(*actql_runtime_operation_fn)(actql_packaged_runtime *);
typedef actql_control_host *(*actql_runtime_host_fn)(actql_packaged_runtime_reply *);
typedef actql_parent_read *(*actql_runtime_read_fn)(actql_packaged_runtime_reply *);
typedef actql_packaged_runtime *(*actql_runtime_original_fn)(actql_packaged_runtime_reply *);
typedef int32_t (*actql_runtime_tag_fn)(actql_packaged_runtime_reply *);
void actql_native_control_register_packaged_runtime_roots(
    actql_runtime_capture_fn, actql_runtime_operation_fn, actql_runtime_operation_fn,
    actql_runtime_host_fn, actql_runtime_read_fn, actql_runtime_original_fn,
    actql_runtime_tag_fn, actql_runtime_tag_fn);

/* Bounded exact UTF-16 input, without locale conversion or normalization.
 * These copies belong to the outer control lifetime, never the read grant. */
int actql_packaged_runtime_capture_utf16_into(actql_control_host *, actql_parent_read *,
    const uint16_t *, int32_t, const uint16_t *, int32_t,
    const uint16_t *, int32_t, const uint16_t *, int32_t,
    int32_t, actql_packaged_runtime_reply **);
int actql_packaged_runtime_current_into(actql_packaged_runtime *, actql_packaged_runtime_reply **);
int actql_packaged_runtime_close_into(actql_packaged_runtime *, actql_packaged_runtime_reply **);
int actql_packaged_runtime_originals_into(actql_packaged_runtime_reply *,
    actql_control_host **, actql_parent_read **, actql_packaged_runtime **);
int32_t actql_packaged_runtime_operation(actql_packaged_runtime_reply *);
int32_t actql_packaged_runtime_issue_family(actql_packaged_runtime_reply *);
int actql_packaged_runtime_drop_reply(actql_packaged_runtime_reply **,
    actql_control_host *, actql_parent_read *, actql_packaged_runtime *);
/* Inner Runtime close only. Parent read/Host ownership remains independent. */
int actql_packaged_runtime_finish_closed_data(actql_control_host **,
    actql_parent_read **, actql_packaged_runtime **, actql_packaged_runtime_reply **);
int actql_packaged_runtime_finish_refused_capture(actql_control_host **,
    actql_parent_read **, actql_packaged_runtime_reply **);
#endif
