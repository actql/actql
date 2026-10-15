#ifndef ACTQL_PRIVATE_SQLITE_SHIM_H
#define ACTQL_PRIVATE_SQLITE_SHIM_H
#include "domain_read_shim.h"
/* Actual regular Source3dfb3ea8, C SHA256
 * 0ebf0609eac6ccfef7d576a7ecb9ce5e04d5887dc92bd946254445fc9a8db420.
 * These callbacks borrow managed inputs; original getters return owned refs.
 * No generated field/layout inspection or separate provider is used. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control25InstalledArenaSqliteReply actql_sqlite_reply;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control27InstalledArenaSqliteLibrary actql_sqlite_original;
typedef actql_sqlite_reply *(*actql_sqlite_prepare_fn)(actql_control_host *, actql_domain *, moonbit_string_t, int64_t, int32_t);
typedef actql_sqlite_reply *(*actql_sqlite_operation_fn)(actql_control_host *, actql_sqlite_original *);
typedef actql_control_host *(*actql_sqlite_host_fn)(actql_sqlite_reply *);
typedef actql_domain *(*actql_sqlite_domain_fn)(actql_sqlite_reply *);
typedef actql_sqlite_original *(*actql_sqlite_original_fn)(actql_sqlite_reply *);
typedef int32_t (*actql_sqlite_tag_fn)(actql_sqlite_reply *);
void actql_native_control_register_sqlite_roots(actql_sqlite_prepare_fn,
    actql_sqlite_operation_fn, actql_sqlite_operation_fn, actql_sqlite_host_fn,
    actql_sqlite_domain_fn, actql_sqlite_original_fn, actql_sqlite_tag_fn, actql_sqlite_tag_fn);
/* Trusted same-domain whole managed caller only: retain existing read scope
 * through path/reply/copy/drop. A raw UTF-16 path creates no installed trust. */
int actql_sqlite_prepare_utf16_into(actql_control_host *, actql_domain *,
    const uint16_t *, int32_t, int64_t, int32_t, actql_sqlite_reply **);
int actql_sqlite_current_into(actql_control_host *, actql_sqlite_original *, actql_sqlite_reply **);
int actql_sqlite_close_into(actql_control_host *, actql_sqlite_original *, actql_sqlite_reply **);
int actql_sqlite_originals_into(actql_sqlite_reply *, actql_control_host **, actql_domain **, actql_sqlite_original **);
int32_t actql_sqlite_operation(actql_sqlite_reply *);
int32_t actql_sqlite_issue_family(actql_sqlite_reply *);
int actql_sqlite_drop_reply(actql_sqlite_reply **, actql_control_host *, actql_domain *, actql_sqlite_original *);
/* Data-only release AFTER same-original Close/Ok, or Prepare refusal with no
 * Library. Slot clearing precedes decref; no implicit physical close/retry. */
int actql_sqlite_finish_closed_data(actql_control_host **, actql_domain **,
    actql_sqlite_original **, actql_sqlite_reply **);
int actql_sqlite_finish_refused_prepare(actql_control_host **, actql_domain **, actql_sqlite_reply **);
#endif
