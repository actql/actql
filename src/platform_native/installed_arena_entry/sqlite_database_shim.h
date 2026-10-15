#ifndef ACTQL_PRIVATE_SQLITE_DATABASE_SHIM_H
#define ACTQL_PRIVATE_SQLITE_DATABASE_SHIM_H
#include "sqlite_shim.h"
/* Observed regular Source812f3ab6 C SHA256
 * 9a05670f08559799a78af8caa9fb58ea76983eadb13e62b1e1768ec8b918e9ea.
 * Code callbacks borrow inputs; reply/original/body getters return owned refs.
 * No generated object layout or independently linked provider is used. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control28InstalledArenaSqliteDatabase actql_sqlite_database;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control33InstalledArenaSqliteDatabaseReply actql_sqlite_database_reply;
typedef actql_sqlite_database_reply *(*actql_database_restore_fn)(actql_control_host *, actql_sqlite_original *, moonbit_string_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_database_initialize_fn)(actql_control_host *, actql_sqlite_original *, moonbit_string_t, int64_t, uint64_t, uint64_t);
typedef actql_sqlite_database_reply *(*actql_database_operation_fn)(actql_control_host *, actql_sqlite_database *);
typedef actql_sqlite_database_reply *(*actql_database_read_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_database_insert_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, moonbit_bytes_t);
typedef actql_sqlite_database_reply *(*actql_database_compare_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, int64_t, moonbit_bytes_t);
typedef actql_sqlite_database_reply *(*actql_database_transaction_fn)(actql_control_host *, actql_sqlite_database *, int32_t);
typedef actql_control_host *(*actql_database_host_fn)(actql_sqlite_database_reply *);
typedef actql_sqlite_original *(*actql_database_library_fn)(actql_sqlite_database_reply *);
typedef actql_sqlite_database *(*actql_database_original_fn)(actql_sqlite_database_reply *);
typedef int32_t (*actql_database_tag_fn)(actql_sqlite_database_reply *);
typedef int64_t (*actql_database_scalar_fn)(actql_sqlite_database_reply *);
typedef moonbit_bytes_t (*actql_database_body_fn)(actql_sqlite_database_reply *);
typedef actql_sqlite_database_reply *(*actql_database_reserve_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, int64_t, int64_t, int64_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_database_usage_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t);
typedef actql_sqlite_database_reply *(*actql_database_release_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, int64_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_database_lookup_capacity_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t);
void actql_native_control_register_sqlite_database_roots(
    actql_database_restore_fn, actql_database_initialize_fn, actql_database_operation_fn,
    actql_database_read_fn, actql_database_insert_fn, actql_database_compare_fn,
    actql_database_transaction_fn, actql_database_operation_fn, actql_database_operation_fn,
    actql_database_host_fn, actql_database_library_fn, actql_database_original_fn,
    actql_database_tag_fn, actql_database_tag_fn, actql_database_tag_fn, actql_database_tag_fn,
    actql_database_tag_fn, actql_database_scalar_fn, actql_database_body_fn, actql_database_scalar_fn,
    actql_database_read_fn, actql_database_body_fn,
    actql_database_reserve_fn, actql_database_usage_fn, actql_database_release_fn,
    actql_database_tag_fn, actql_database_scalar_fn, actql_database_scalar_fn,
    actql_database_lookup_capacity_fn, actql_database_operation_fn, actql_database_operation_fn,
    actql_database_scalar_fn, actql_database_scalar_fn, actql_database_scalar_fn, actql_database_tag_fn);
/* Acquire outside a managed child scope, as with the original Library. Path
 * is bounded trusted control metadata. Existing-only restore never creates.
 * Initialize requires the trusted adoption caller's original owned file facts;
 * device/inode do not themselves grant initialization authority. */
int actql_sqlite_database_restore_utf16_into(actql_control_host *, actql_sqlite_original *,
    const uint16_t *, int32_t, int64_t, actql_sqlite_database_reply **);
int actql_sqlite_database_initialize_utf16_into(actql_control_host *, actql_sqlite_original *,
    const uint16_t *, int32_t, int64_t, uint64_t, uint64_t, actql_sqlite_database_reply **);
/* Managed row input/output must stay inside the original funded read scope.
 * Core validates that same scope/Host/Database before the first input copy.
 * A refused preflight, or body exceeding its original bound, returns its
 * original Observe(3) reply; verify the operation AND bound, never treat it as
 * a read/write ACK. No arbitrary SQL or retry is exposed. */
int actql_sqlite_database_read_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t, actql_sqlite_database_reply **);
/* Exact existing cursor; empty is the first row. NotFound is only the
 * original query result, not a namespace completeness/admission fact. */
int actql_sqlite_database_scan_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t, actql_sqlite_database_reply **);
int actql_sqlite_database_insert_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, const unsigned char *, int64_t,
    actql_sqlite_database_reply **);
int actql_sqlite_database_compare_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t,
    const unsigned char *, int64_t, actql_sqlite_database_reply **);
int actql_sqlite_database_transaction_into(actql_control_host *, actql_sqlite_database *, int32_t, actql_sqlite_database_reply **);
int actql_sqlite_database_observe_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
int actql_sqlite_database_fence_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
/* Cleanup is outside the managed caller scope. The original Core owns entry,
 * failed leave recovery and physical close; transport zero is not its ACK. */
int actql_sqlite_database_close_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
int actql_sqlite_database_originals_into(actql_sqlite_database_reply *, actql_control_host **,
    actql_sqlite_original **, actql_sqlite_database **);
int32_t actql_sqlite_database_operation(actql_sqlite_database_reply *);
int32_t actql_sqlite_database_stage(actql_sqlite_database_reply *);
int32_t actql_sqlite_database_issue_family(actql_sqlite_database_reply *);
int32_t actql_sqlite_database_after_issue_family(actql_sqlite_database_reply *);
int32_t actql_sqlite_database_has_row(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_revision(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_body_bound(actql_sqlite_database_reply *);
/* Copy to caller's existing buffer, bounded by the exact original Database
 * and reply. Empty present rows remain distinct from absent rows. Does not
 * retire SQLite's result_body, acknowledge COMMIT or grant Result read. */
int actql_sqlite_database_copy_row(actql_sqlite_database_reply *, actql_control_host *,
    actql_sqlite_original *, actql_sqlite_database *, unsigned char *, int64_t, int64_t *);
/* Same original/current validation and managed lifetime as body copy. Key
 * output is exact UTF-8, bounded by the existing 512-byte SQLite key contract. */
int actql_sqlite_database_copy_key(actql_sqlite_database_reply *, actql_control_host *,
    actql_sqlite_original *, actql_sqlite_database *, unsigned char *, int64_t, int64_t *);
/* Physical reservation rows in the SAME active caller transaction. No
 * implicit BEGIN/COMMIT/ROLLBACK, grant, cleanup acknowledgement or retry. */
int actql_sqlite_database_capacity_reserve_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t, int64_t, int64_t, int64_t,
    actql_sqlite_database_reply **);
int actql_sqlite_database_capacity_usage_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, actql_sqlite_database_reply **);
int actql_sqlite_database_capacity_release_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t, int64_t,
    actql_sqlite_database_reply **);
/* -1 means absent DATA; 0 is a valid unchanged/zero observation. */
int32_t actql_sqlite_database_capacity_changed(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_reserved_bytes(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_reserved_objects(actql_sqlite_database_reply *);
/* Read-only physical DATA in the same original connection. Totals span this
 * database's namespaces; they are not an admitted inventory or free credit.
 * Transaction state is not COMMIT/rollback/cleanup acknowledgment. */
int actql_sqlite_database_capacity_read_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, actql_sqlite_database_reply **);
int actql_sqlite_database_database_usage_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
int actql_sqlite_database_transaction_state_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
int64_t actql_sqlite_database_record_count(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_record_body_bytes(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_reservation_count(actql_sqlite_database_reply *);
int32_t actql_sqlite_database_transaction_active(actql_sqlite_database_reply *);
int actql_sqlite_database_drop_reply(actql_sqlite_database_reply **, actql_control_host *,
    actql_sqlite_original *, actql_sqlite_database *);
int actql_sqlite_database_finish_closed_data(actql_control_host **, actql_sqlite_original **,
    actql_sqlite_database **, actql_sqlite_database_reply **);
int actql_sqlite_database_finish_refused_open(actql_control_host **, actql_sqlite_original **,
    actql_sqlite_database_reply **);
#endif
