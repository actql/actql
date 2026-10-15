#ifndef ACTQL_PRIVATE_WORKER_SELECTION_SHIM_H
#define ACTQL_PRIVATE_WORKER_SELECTION_SHIM_H
#include "control_shim.h"
/* Actual Sourcef16d7207 regular C SHA256
 * 4648401c25be5dd33697973b7c9a96bb758eed0f9ba96e8c173c96b9ae03a43f.
 * Inputs are borrowed; getters return owned references (nullable selection).
 * This is private same-component metadata transport, never pointer wire. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control29InstalledArenaWorkerSelection actql_worker_selection;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control34InstalledArenaWorkerSelectionReply actql_worker_selection_reply;
typedef actql_worker_selection_reply *(*actql_worker_select_fn)(actql_control_host *);
typedef actql_worker_selection_reply *(*actql_worker_current_fn)(actql_control_host *, actql_worker_selection *);
typedef actql_control_host *(*actql_worker_host_fn)(actql_worker_selection_reply *);
typedef actql_worker_selection *(*actql_worker_original_fn)(actql_worker_selection_reply *);
typedef actql_control_host *(*actql_worker_parent_fn)(actql_worker_selection *);
typedef int32_t (*actql_worker_tag_fn)(actql_worker_selection_reply *);
void actql_native_control_register_worker_selection_roots(
    actql_worker_select_fn, actql_worker_current_fn, actql_worker_host_fn,
    actql_worker_original_fn, actql_worker_parent_fn,
    actql_worker_tag_fn, actql_worker_tag_fn);
int actql_worker_select_into(actql_control_host *, actql_worker_selection_reply **);
int actql_worker_selection_current_into(actql_control_host *, actql_worker_selection *, actql_worker_selection_reply **);
int actql_worker_selection_originals_into(actql_worker_selection_reply *, actql_control_host **, actql_worker_selection **);
int32_t actql_worker_selection_operation(actql_worker_selection_reply *);
int32_t actql_worker_selection_issue_family(actql_worker_selection_reply *);
int actql_worker_selection_drop_reply(actql_worker_selection_reply **, actql_control_host *, actql_worker_selection *);
/* Owning reference retirement only: no Host/worker close, current call,
 * resource return, physical ACK, lost-COMMIT lookup, permit or settlement. */
int actql_worker_selection_finish_data(actql_control_host **, actql_worker_selection **, actql_worker_selection_reply **);
#endif
