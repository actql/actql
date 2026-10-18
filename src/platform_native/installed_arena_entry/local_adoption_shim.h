#ifndef ACTQL_PRIVATE_LOCAL_ADOPTION_SHIM_H
#define ACTQL_PRIVATE_LOCAL_ADOPTION_SHIM_H
#include "local_host_resources_shim.h"

/* Opaque tags confirmed by matching regular Native C. Never inspect fields. */
typedef struct _M0TP45actql5actql16platform__native12client__host26NativeLocalAdoptionBinding actql_adoption_binding;
typedef struct _M0TP45actql5actql16platform__native12client__host31NativeLocalAdoptionBindingReply actql_adoption_reply;
typedef struct _M0TP45actql5actql16platform__native12client__host26NativeLocalAdoptionSession actql_adoption_session;
typedef struct _M0TP45actql5actql16platform__native12client__host25NativeLocalJournalCapture actql_adoption_journal;
typedef void actql_adoption_crypto;

typedef actql_adoption_binding *(*actql_adoption_prepare_fn)(
    actql_control_host *, actql_local_host_resources *, actql_parent_read *,
    actql_adoption_crypto *, moonbit_string_t, moonbit_string_t, moonbit_string_t,
    moonbit_string_t, moonbit_string_t, moonbit_string_t *, moonbit_string_t,
    int32_t, int32_t);
typedef actql_adoption_reply *(*actql_adoption_operate_fn)(actql_adoption_binding *, int32_t);
typedef actql_adoption_reply *(*actql_adoption_journal_fn)(actql_adoption_binding *, double, int32_t, int64_t);
typedef actql_adoption_binding *(*actql_adoption_original_fn)(actql_adoption_reply *);
typedef actql_control_host *(*actql_adoption_host_fn)(actql_adoption_binding *);
typedef actql_local_host_resources *(*actql_adoption_pair_fn)(actql_adoption_binding *);
typedef actql_parent_read *(*actql_adoption_read_fn)(actql_adoption_binding *);
typedef actql_adoption_crypto *(*actql_adoption_crypto_fn)(actql_adoption_binding *);
typedef actql_adoption_session *(*actql_adoption_session_fn)(actql_adoption_binding *);
typedef actql_adoption_journal *(*actql_adoption_original_journal_fn)(actql_adoption_binding *);
typedef int32_t (*actql_adoption_ack_fn)(actql_adoption_binding *);
typedef int32_t (*actql_adoption_tag_fn)(actql_adoption_reply *);

void actql_native_control_register_local_adoption_binding_roots(
    actql_adoption_prepare_fn, actql_adoption_operate_fn, actql_adoption_journal_fn,
    actql_adoption_original_fn, actql_adoption_host_fn, actql_adoption_pair_fn,
    actql_adoption_read_fn, actql_adoption_crypto_fn, actql_adoption_session_fn,
    actql_adoption_original_journal_fn, actql_adoption_ack_fn,
    actql_adoption_tag_fn, actql_adoption_tag_fn);

/* UTF-16 transport only. Configuration lengths partition the exact supplied
 * units into at most eight paths; no JSON, normalization or second selection. */
int actql_local_adoption_prepare_utf16_into(
    actql_control_host *, actql_local_host_resources *, actql_parent_read *,
    actql_adoption_crypto *, const uint16_t *, int32_t, const uint16_t *, int32_t,
    const uint16_t *, int32_t, const uint16_t *, int32_t, const uint16_t *, int32_t,
    const uint16_t *, int32_t, const int32_t *, int32_t,
    const uint16_t *, int32_t, int32_t, int32_t, actql_adoption_binding **);
int actql_local_adoption_operate_into(actql_adoption_binding *, int32_t, actql_adoption_reply **);
int actql_local_adoption_capture_journal_into(actql_adoption_binding *, double, int32_t, int64_t, actql_adoption_reply **);
int actql_local_adoption_originals_into(actql_adoption_binding *, actql_control_host **,
    actql_local_host_resources **, actql_parent_read **, actql_adoption_crypto **,
    actql_adoption_session **, actql_adoption_journal **);
int actql_local_adoption_drop_originals(actql_adoption_binding *, actql_control_host **,
    actql_local_host_resources **, actql_parent_read **, actql_adoption_crypto **,
    actql_adoption_session **, actql_adoption_journal **);
int32_t actql_local_adoption_operation(actql_adoption_reply *);
int32_t actql_local_adoption_issue_family(actql_adoption_reply *);
int actql_local_adoption_drop_reply(actql_adoption_reply **, actql_adoption_binding *);
int actql_local_adoption_finish_closed_data(actql_adoption_binding **, actql_adoption_reply **);
#endif
