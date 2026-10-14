#ifndef ACTQL_PRIVATE_DOMAIN_SHIM_H
#define ACTQL_PRIVATE_DOMAIN_SHIM_H
#include "backing_shim.h"
/* Actual regular Source8e235ca7 C SHA256
 * 64eccc1426bf717868bd4bfd8508128e4b8bf704bb9708f6aefab263d72f7c36.
 * Managed callback inputs are borrowed; returned references are owned. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control20InstalledArenaDomain actql_domain;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control25InstalledArenaDomainReply actql_domain_reply;
typedef actql_domain_reply *(*actql_domain_prepare_fn)(actql_control_host *, actql_backing_loan *,
    int32_t, int64_t, int32_t, int32_t, int32_t, int64_t, int64_t, int64_t);
typedef actql_domain_reply *(*actql_domain_operation_fn)(actql_control_host *, actql_domain *);
typedef actql_control_host *(*actql_domain_original_fn)(actql_domain_reply *);
typedef actql_domain *(*actql_domain_handle_fn)(actql_domain_reply *);
typedef int32_t (*actql_domain_tag_fn)(actql_domain_reply *);
typedef moonbit_string_t (*actql_domain_description_fn)(actql_domain_reply *);
void actql_native_control_register_domain_roots(
    actql_domain_prepare_fn, actql_domain_operation_fn, actql_domain_operation_fn,
    actql_domain_operation_fn, actql_domain_operation_fn, actql_domain_operation_fn,
    actql_domain_original_fn, actql_domain_handle_fn, actql_domain_tag_fn,
    actql_domain_tag_fn, actql_domain_description_fn);
/* No layout reads, original replacement, FD close or implicit second call. */
int actql_domain_prepare_into(actql_control_host *, actql_backing_loan *, int32_t, int64_t,
    int32_t, int32_t, int32_t, int64_t, int64_t, int64_t, actql_domain_reply **);
int actql_domain_current_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_transfer_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_enter_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_leave_into(actql_control_host *, actql_domain *, actql_domain_reply **);
/* Trusted existing caller only AFTER scoped stop and independent borrower
 * retirement. This forwards Owner cleanup; it never creates those facts. */
int actql_domain_close_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_originals_into(actql_domain_reply *, actql_control_host **, actql_domain **);
int32_t actql_domain_operation(actql_domain_reply *);
int32_t actql_domain_issue_family(actql_domain_reply *);
int actql_domain_drop_reply(actql_domain_reply **, actql_control_host *, actql_domain *);
/* Data drops only after exact same-original Close/Ok, or no-domain Prepare
 * refusal. Slot clearing precedes decref, including lost responses. */
int actql_domain_finish_closed_data(actql_control_host **, actql_domain **, actql_domain_reply **);
int actql_domain_finish_refused_prepare(actql_control_host **, actql_domain_reply **);
#endif
