#ifndef ACTQL_PRIVATE_LIVE_CHANNEL_SHIM_H
#define ACTQL_PRIVATE_LIVE_CHANNEL_SHIM_H
#include "domain_shim.h"

/* Exact regular Sourcef62f257ce C, SHA256
 * 7d29660add49c69be0e428d31d267890459cefb115f7dbe411777d927bc5025e.
 * Callback inputs are borrowed. Reply/Host/domain/channel getters return
 * owned references; the channel result is nullable. Never inspect fields. */
typedef struct _M0TP45actql5actql16platform__native15host__bootstrap23NativeBackedLiveChannelGRP45actql5actql16platform__native25installed__arena__control18InstalledArenaHostRP45actql5actql16platform__native25installed__arena__control20InstalledArenaDomainE actql_live_channel;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control30InstalledArenaLiveChannelReply actql_live_channel_reply;
typedef actql_live_channel_reply *(*actql_live_prepare_fn)(actql_control_host *,
    actql_domain *, int32_t, int32_t, int32_t, int64_t);
typedef actql_live_channel_reply *(*actql_live_bind_fn)(actql_control_host *,
    actql_domain *, actql_live_channel *, int64_t, int64_t, int64_t);
typedef actql_live_channel_reply *(*actql_live_operate_fn)(actql_control_host *,
    actql_domain *, actql_live_channel *, int32_t);
typedef actql_live_channel_reply *(*actql_live_report_fn)(actql_control_host *,
    actql_domain *, actql_live_channel *, int32_t, int32_t, int32_t,
    int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
typedef actql_control_host *(*actql_live_host_fn)(actql_live_channel_reply *);
typedef actql_domain *(*actql_live_domain_fn)(actql_live_channel_reply *);
typedef actql_live_channel *(*actql_live_channel_fn)(actql_live_channel_reply *);
typedef int32_t (*actql_live_tag_fn)(actql_live_channel_reply *);
typedef int64_t (*actql_live_limit_fn)(actql_live_channel_reply *, int32_t);
typedef moonbit_string_t (*actql_live_description_fn)(actql_live_channel_reply *);
void actql_native_control_register_live_channel_roots(
    actql_live_prepare_fn, actql_live_bind_fn, actql_live_operate_fn,
    actql_live_report_fn, actql_live_host_fn, actql_live_domain_fn,
    actql_live_channel_fn, actql_live_tag_fn, actql_live_tag_fn,
    actql_live_tag_fn, actql_live_limit_fn, actql_live_description_fn);

/* Existing trusted physical caller only. Persistent caller-owned slots are
 * populated before return; no slot is overwritten and no command is retried.
 * These are component-local opaque references, never public Wire pointers. */
int actql_live_channel_prepare_into(actql_control_host *, actql_domain *,
    int32_t, int32_t, int32_t, int64_t, actql_live_channel_reply **);
int actql_live_channel_bind_into(actql_control_host *, actql_domain *,
    actql_live_channel *, int64_t, int64_t, int64_t, actql_live_channel_reply **);
int actql_live_channel_operate_into(actql_control_host *, actql_domain *,
    actql_live_channel *, int32_t, actql_live_channel_reply **);
int actql_live_channel_report_into(actql_control_host *, actql_domain *,
    actql_live_channel *, int32_t, int32_t, int32_t, int64_t, int64_t, int64_t,
    int64_t, int64_t, int64_t, int64_t, actql_live_channel_reply **);
int actql_live_channel_originals_into(actql_live_channel_reply *,
    actql_control_host **, actql_domain **, actql_live_channel **);
int32_t actql_live_channel_operation(actql_live_channel_reply *);
int32_t actql_live_channel_issue_family(actql_live_channel_reply *);
/* Checked immutable DATA only; these getters do not refresh current/grants. */
int actql_live_channel_copy_state(actql_live_channel_reply *, actql_control_host *,
    actql_domain *, actql_live_channel *, int32_t *);
int actql_live_channel_copy_limits(actql_live_channel_reply *, actql_control_host *,
    actql_domain *, actql_live_channel *, int64_t[6]);
int actql_live_channel_drop_reply(actql_live_channel_reply **,
    actql_control_host *, actql_domain *, actql_live_channel *);
/* Drop extra aliases only after the exact same-original typed Retire/Ok, or
 * a no-channel Prepare refusal. No process/FD/Store/loan close or ACK here. */
int actql_live_channel_finish_retired_data(actql_control_host **, actql_domain **,
    actql_live_channel **, actql_live_channel_reply **);
int actql_live_channel_finish_refused_prepare(actql_control_host **,
    actql_domain **, actql_live_channel_reply **);
#endif
