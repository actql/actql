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

#include "packaged_runtime_abi.generated.h"
#endif
