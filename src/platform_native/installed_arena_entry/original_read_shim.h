#ifndef ACTQL_PRIVATE_ORIGINAL_READ_SHIM_H
#define ACTQL_PRIVATE_ORIGINAL_READ_SHIM_H
#include "domain_shim.h"
/* Actual Source eb1650c70 regular C5876434 bytes / SHA256
 * fe55b57746c9add0b57b3ccc0c9786539d922e86fd33f40f59f608a8df2dcb19.
 * Callback inputs borrow originals; replies and getter outputs are owned.
 * The optional original is NULL for no-carrier refusal. No object layout reads. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control26InstalledArenaOriginalRead actql_parent_read;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control31InstalledArenaOriginalReadReply actql_parent_read_reply;
typedef actql_parent_read_reply *(*actql_parent_read_prepare_fn)(actql_control_host *, actql_domain *,
    int64_t, int64_t, int64_t, int64_t, int64_t);
typedef actql_parent_read_reply *(*actql_parent_read_operation_fn)(actql_control_host *, actql_parent_read *);
typedef actql_control_host *(*actql_parent_read_host_fn)(actql_parent_read_reply *);
typedef actql_domain *(*actql_parent_read_domain_fn)(actql_parent_read_reply *);
typedef actql_parent_read *(*actql_parent_read_original_fn)(actql_parent_read_reply *);
typedef int32_t (*actql_parent_read_tag_fn)(actql_parent_read_reply *);
void actql_native_control_register_parent_read_roots(
    actql_parent_read_prepare_fn, actql_parent_read_operation_fn,
    actql_parent_read_operation_fn, actql_parent_read_operation_fn,
    actql_parent_read_operation_fn, actql_parent_read_operation_fn,
    actql_parent_read_host_fn, actql_parent_read_domain_fn,
    actql_parent_read_original_fn, actql_parent_read_tag_fn, actql_parent_read_tag_fn);
int actql_parent_read_prepare_into(actql_control_host *, actql_domain *,
    int64_t, int64_t, int64_t, int64_t, int64_t, actql_parent_read_reply **);
int actql_parent_read_current_into(actql_control_host *, actql_parent_read *, actql_parent_read_reply **);
int actql_parent_read_enter_into(actql_control_host *, actql_parent_read *, actql_parent_read_reply **);
int actql_parent_read_leave_into(actql_control_host *, actql_parent_read *, actql_parent_read_reply **);
int actql_parent_read_cleanup_into(actql_control_host *, actql_parent_read *, actql_parent_read_reply **);
int actql_parent_read_close_into(actql_control_host *, actql_parent_read *, actql_parent_read_reply **);
int actql_parent_read_originals_into(actql_parent_read_reply *, actql_control_host **,
    actql_domain **, actql_parent_read **);
int32_t actql_parent_read_operation(actql_parent_read_reply *);
int32_t actql_parent_read_issue_family(actql_parent_read_reply *);
int actql_parent_read_drop_reply(actql_parent_read_reply **, actql_control_host *, actql_domain *, actql_parent_read *);
/* Only confirmed same-original Close/Ok or no-carrier Prepare refusal drops
 * owned data. Clear persistent slots before every decref; never close here. */
int actql_parent_read_finish_closed_data(actql_control_host **, actql_domain **,
    actql_parent_read **, actql_parent_read_reply **);
int actql_parent_read_finish_refused_prepare(actql_control_host **, actql_domain **,
    actql_parent_read_reply **);
#endif
