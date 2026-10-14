#ifndef ACTQL_PRIVATE_BACKING_SHIM_H
#define ACTQL_PRIVATE_BACKING_SHIM_H

#include "control_shim.h"

/* Exact Source674 regular C, run-6xXQbc, SHA256
 * 5c3c5820cad4e89163cd8570401f812f3af7fb29cc51758fb71f8c7bfbecd3b0.
 * Managed inputs are borrowed; returned non-NULL references are owned.
 * These are opaque generated tags, never user pointers or copied layouts. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control26InstalledArenaBackingReply actql_backing_reply;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control27InstalledArenaBackingBorrow actql_backing_loan;

typedef actql_backing_reply *(*actql_backing_borrow_fn)(actql_control_host *);
typedef actql_backing_reply *(*actql_backing_operation_fn)(actql_control_host *, actql_backing_loan *);
typedef actql_control_host *(*actql_backing_original_fn)(actql_backing_reply *);
typedef actql_backing_loan *(*actql_backing_loan_fn)(actql_backing_reply *);
typedef int32_t (*actql_backing_tag_fn)(actql_backing_reply *);
typedef moonbit_string_t (*actql_backing_description_fn)(actql_backing_reply *);

/* Code registration only, using the same component/provider as control_shim.
 * No supplier adoption, loan acquisition, permission or physical allocation. */
void actql_native_control_register_backing_roots(
    actql_backing_borrow_fn, actql_backing_operation_fn,
    actql_backing_operation_fn, actql_backing_original_fn,
    actql_backing_loan_fn, actql_backing_tag_fn,
    actql_backing_tag_fn, actql_backing_description_fn);

/* Empty persistent slots only. Call status is transport availability, never
 * the Owner's operation outcome. The typed reply remains owned on refusal. */
int actql_backing_borrow_into(actql_control_host *, actql_backing_reply **);
int actql_backing_current_into(actql_control_host *, actql_backing_loan *, actql_backing_reply **);
/* The trusted physical caller invokes return only after the same use stops.
 * No process stop, Host close, Run cancel or Store ACK is inferred here. */
int actql_backing_return_into(actql_control_host *, actql_backing_loan *, actql_backing_reply **);
int actql_backing_originals_into(actql_backing_reply *, actql_control_host **, actql_backing_loan **);
int32_t actql_backing_operation(actql_backing_reply *);
int32_t actql_backing_issue_family(actql_backing_reply *);
moonbit_string_t actql_backing_description(actql_backing_reply *);

/* Data drops only. A live loan reply requires the same independently retained
 * loan and Host. Exact Return/Ok has already returned the logical loan, so its
 * proof can be dropped after the owning loan slot has been cleared. */
int actql_backing_drop_reply(actql_backing_reply **, actql_control_host *, actql_backing_loan *);
/* Clear/drop one owning loan reference only after exact typed Return/Ok.
 * A second alias can use that same proof without another Owner return call.
 * The return reply stays owned by the caller until independently dropped. */
int actql_backing_drop_returned_loan(actql_backing_loan **, actql_backing_reply *, actql_control_host *);

#endif
