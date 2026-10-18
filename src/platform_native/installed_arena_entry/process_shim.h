#ifndef ACTQL_PRIVATE_PROCESS_SHIM_H
#define ACTQL_PRIVATE_PROCESS_SHIM_H
#include "live_channel_shim.h"

/* Actual regular Sourceb3fbe876 C SHA256
 * 7637fabcf76bd03e05125f9a9def083399d3804d5705f2857fe6aea2de919988.
 * Managed callback inputs are borrowed; reply and original getters return
 * owned references (nullable process/channel/frame use NULL). No layouts. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control21InstalledArenaProcess actql_process;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control26InstalledArenaProcessReply actql_process_reply;
typedef actql_process_reply *(*actql_process_prepare_fn)(actql_control_host *, actql_domain *, moonbit_string_t, int32_t, int64_t, int64_t, int64_t);
typedef actql_process_reply *(*actql_process_operate_fn)(actql_control_host *, actql_domain *, actql_process *, int32_t);
typedef actql_process_reply *(*actql_process_child_fn)(actql_control_host *, actql_domain *, actql_process *, moonbit_string_t, moonbit_bytes_t, moonbit_bytes_t);
typedef actql_control_host *(*actql_process_host_fn)(actql_process_reply *);
typedef actql_domain *(*actql_process_domain_fn)(actql_process_reply *);
typedef actql_process *(*actql_process_original_fn)(actql_process_reply *);
typedef actql_live_channel *(*actql_process_channel_fn)(actql_process_reply *);
typedef actql_original_child_frame *(*actql_process_frame_fn)(actql_process_reply *);
typedef int32_t (*actql_process_tag_fn)(actql_process_reply *);
typedef int32_t (*actql_process_descriptor_fn)(actql_process_reply *, int32_t);
typedef moonbit_string_t (*actql_process_description_fn)(actql_process_reply *);
void actql_native_control_register_process_roots(
    actql_process_prepare_fn, actql_process_operate_fn, actql_process_child_fn,
    actql_process_host_fn, actql_process_domain_fn, actql_process_original_fn,
    actql_process_channel_fn, actql_process_frame_fn, actql_process_tag_fn,
    actql_process_tag_fn, actql_process_descriptor_fn, actql_process_tag_fn,
    actql_process_tag_fn, actql_process_description_fn);

/* Trusted original physical assembly only, after independent funding. Persistent
 * caller-owned empty slots retain every returned original despite reply loss.
 * These copies belong to its existing control envelope, never to arena quota. */
int actql_process_prepare_utf16_into(actql_control_host *, actql_domain *,
    const uint16_t *, int32_t, int32_t, int64_t, int64_t, int64_t, actql_process_reply **);
int actql_process_operate_into(actql_control_host *, actql_domain *, actql_process *, int32_t, actql_process_reply **);
int actql_process_child_utf16_into(actql_control_host *, actql_domain *, actql_process *,
    const uint16_t *, int32_t, const uint8_t *, int32_t, const uint8_t *, int32_t,
    actql_process_reply **);
int actql_process_originals_into(actql_process_reply *, actql_control_host **,
    actql_domain **, actql_process **, actql_live_channel **, actql_original_child_frame **);
int32_t actql_process_operation(actql_process_reply *);
int32_t actql_process_issue_family(actql_process_reply *);
/* Historical checked DATA: writer/read/backing/operation observation. Exact
 * operation6 is running1/stopped2; operation12 is stop-request0/1, never a stop
 * or retirement ACK. No current or ACK inference from these scalars. */
int actql_process_copy_facts(actql_process_reply *, actql_control_host *, actql_domain *,
    actql_process *, int32_t[4]);
int actql_process_drop_reply(actql_process_reply **, actql_control_host *, actql_domain *, actql_process *);
/* Only typed same-original operation7/8 Ok, or no-process preparation refusal,
 * may retire these extra aliases. No physical close, stop or provider call. */
int actql_process_finish_closed_data(actql_control_host **, actql_domain **,
    actql_process **, actql_live_channel **, actql_original_child_frame **, actql_process_reply **);
int actql_process_finish_refused_prepare(actql_control_host **, actql_domain **, actql_process_reply **);
#endif
