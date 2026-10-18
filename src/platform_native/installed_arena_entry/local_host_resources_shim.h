#ifndef ACTQL_PRIVATE_LOCAL_HOST_RESOURCES_SHIM_H
#define ACTQL_PRIVATE_LOCAL_HOST_RESOURCES_SHIM_H
#include "original_read_shim.h"
#include "sqlite_shim.h"

/* Opaque tags only. The producer includes this header with the matching
 * emitted Core, so callback type mismatches fail before loading the library.
 * Callbacks borrow inputs; reply and getter outputs are owned references.
 * Both original Hosts remain distinct roles even when their values coincide. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control32InstalledArenaLocalHostResources actql_local_host_resources;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control37InstalledArenaLocalHostResourcesReply actql_local_host_resources_reply;
typedef actql_local_host_resources_reply *(*actql_host_resources_bind_fn)(
    actql_control_host *, actql_parent_read *, actql_sqlite_original *);
typedef actql_local_host_resources_reply *(*actql_host_resources_operate_fn)(
    actql_control_host *, actql_local_host_resources *, int32_t);
typedef actql_control_host *(*actql_host_resources_host_fn)(actql_local_host_resources_reply *);
typedef actql_parent_read *(*actql_host_resources_read_fn)(actql_local_host_resources_reply *);
typedef actql_sqlite_original *(*actql_host_resources_sqlite_fn)(actql_local_host_resources_reply *);
typedef actql_local_host_resources *(*actql_host_resources_original_fn)(actql_local_host_resources_reply *);
typedef int32_t (*actql_host_resources_tag_fn)(actql_local_host_resources_reply *);
typedef int64_t (*actql_host_resources_capacity_fn)(actql_control_host *, int32_t);

void actql_native_control_register_local_host_resource_roots(
    actql_host_resources_bind_fn, actql_host_resources_operate_fn,
    actql_host_resources_host_fn, actql_host_resources_host_fn,
    actql_host_resources_read_fn, actql_host_resources_sqlite_fn,
    actql_host_resources_original_fn, actql_host_resources_tag_fn,
    actql_host_resources_tag_fn, actql_host_resources_tag_fn, actql_host_resources_tag_fn,
    actql_host_resources_capacity_fn);

int actql_host_resources_bind_into(actql_control_host *, actql_parent_read *,
    actql_sqlite_original *, actql_local_host_resources_reply **);
int actql_host_resources_operate_into(actql_control_host *, actql_local_host_resources *,
    int32_t, actql_local_host_resources_reply **);
int actql_host_resources_originals_into(actql_local_host_resources_reply *,
    actql_control_host **, actql_control_host **, actql_parent_read **,
    actql_sqlite_original **, actql_local_host_resources **);
int32_t actql_host_resources_operation(actql_local_host_resources_reply *);
int32_t actql_host_resources_issue_origin(actql_local_host_resources_reply *);
int32_t actql_host_resources_issue_family(actql_local_host_resources_reply *);
int32_t actql_host_resources_close_confirmed(actql_local_host_resources_reply *);
int64_t actql_host_resources_capacity_scalar(actql_control_host *, int32_t);
int actql_host_resources_drop_reply(actql_local_host_resources_reply **,
    actql_control_host *, actql_control_host *, actql_parent_read *,
    actql_sqlite_original *, actql_local_host_resources *);
/* Data-only release after exact same-original Close/ACK. It never performs
 * physical cleanup, returns a loan or acknowledges a business operation. */
int actql_host_resources_finish_closed_data(actql_control_host **,
    actql_control_host **, actql_parent_read **, actql_sqlite_original **,
    actql_local_host_resources **, actql_local_host_resources_reply **);
#endif
