#ifndef ACTQL_PRIVATE_SQLITE_DATABASE_SHIM_H
#define ACTQL_PRIVATE_SQLITE_DATABASE_SHIM_H
#include "sqlite_shim.h"
/* Observed regular Source1c4d0dc7 C SHA256
 * 0f1adca4cfaf73cd97509d642a9743d58af2c5d33354990d78876c9f1b9836c7.
 * All 52 callback parameters use actual emitted prototypes. Inputs borrow;
 * reply/original/lookup/body getters return owned refs (nullable lookup).
 * No managed struct layout or independently linked provider is used. */
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
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control26InstalledArenaSqliteLookup actql_sqlite_lookup;
typedef actql_sqlite_database_reply *(*actql_database_reserve_bounded_fn)(actql_control_host *, actql_sqlite_database *, moonbit_string_t, moonbit_string_t, int64_t, int64_t, int64_t, int64_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_lookup_operation_fn)(actql_control_host *, actql_sqlite_lookup *);
typedef actql_sqlite_database_reply *(*actql_lookup_read_fn)(actql_control_host *, actql_sqlite_lookup *, moonbit_string_t, moonbit_string_t, int64_t);
typedef actql_sqlite_database_reply *(*actql_lookup_key_fn)(actql_control_host *, actql_sqlite_lookup *, moonbit_string_t, moonbit_string_t);
typedef actql_sqlite_database_reply *(*actql_lookup_usage_fn)(actql_control_host *, actql_sqlite_lookup *, moonbit_string_t);
typedef actql_sqlite_lookup *(*actql_database_lookup_fn)(actql_sqlite_database_reply *);
typedef actql_sqlite_database_reply *(*actql_database_revalidate_fn)(actql_sqlite_database_reply *);
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
    actql_database_scalar_fn, actql_database_scalar_fn, actql_database_scalar_fn, actql_database_tag_fn,
    actql_database_lookup_capacity_fn, actql_database_tag_fn, actql_database_scalar_fn,
    actql_database_operation_fn, actql_database_reserve_bounded_fn,
    actql_database_operation_fn, actql_lookup_operation_fn,
    actql_lookup_read_fn, actql_lookup_read_fn, actql_lookup_key_fn, actql_lookup_key_fn,
    actql_lookup_usage_fn, actql_lookup_operation_fn, actql_lookup_operation_fn,
    actql_lookup_operation_fn, actql_database_lookup_fn, actql_database_revalidate_fn);
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

/* Ordinary confirmed byte-store metadata/read-TX operations. These preserve
 * the original fence; they are not the active-fenced lookup exception. */
int actql_sqlite_database_header_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, actql_sqlite_database_reply **);
int32_t actql_sqlite_database_has_header(actql_sqlite_database_reply *);
int64_t actql_sqlite_database_header_body_bytes(actql_sqlite_database_reply *);
int actql_sqlite_database_begin_read_into(actql_control_host *, actql_sqlite_database *, actql_sqlite_database_reply **);
int actql_sqlite_database_capacity_reserve_bounded_utf16_into(actql_control_host *, actql_sqlite_database *,
    const uint16_t *, int32_t, const uint16_t *, int32_t, int64_t, int64_t,
    int64_t, int64_t, int64_t, actql_sqlite_database_reply **);
/* Start/cleanup outside the caller's managed scope, like Database custody.
 * All read/finish calls stay inside that SAME original funded scope. A new
 * child is available only from Core's retained start reply, never a scalar. */
/* Both persistent out-slots are populated inside the same foreign call;
 * a lost Python response must not lose the pending original child. */
int actql_sqlite_lookup_start_into(actql_control_host *, actql_sqlite_database *,
    actql_sqlite_lookup **, actql_sqlite_database_reply **);
int actql_sqlite_database_lookup_into(actql_sqlite_database_reply *, actql_sqlite_lookup **);
int actql_sqlite_lookup_observe_into(actql_control_host *, actql_sqlite_lookup *, actql_sqlite_database_reply **);
int actql_sqlite_lookup_read_utf16_into(actql_control_host *, actql_sqlite_lookup *, const uint16_t *, int32_t,
    const uint16_t *, int32_t, int64_t, actql_sqlite_database_reply **);
int actql_sqlite_lookup_scan_utf16_into(actql_control_host *, actql_sqlite_lookup *, const uint16_t *, int32_t,
    const uint16_t *, int32_t, int64_t, actql_sqlite_database_reply **);
int actql_sqlite_lookup_header_utf16_into(actql_control_host *, actql_sqlite_lookup *, const uint16_t *, int32_t,
    const uint16_t *, int32_t, actql_sqlite_database_reply **);
int actql_sqlite_lookup_capacity_utf16_into(actql_control_host *, actql_sqlite_lookup *, const uint16_t *, int32_t,
    const uint16_t *, int32_t, actql_sqlite_database_reply **);
int actql_sqlite_lookup_capacity_usage_utf16_into(actql_control_host *, actql_sqlite_lookup *, const uint16_t *, int32_t,
    actql_sqlite_database_reply **);
int actql_sqlite_lookup_database_usage_into(actql_control_host *, actql_sqlite_lookup *, actql_sqlite_database_reply **);
int actql_sqlite_lookup_finish_into(actql_control_host *, actql_sqlite_lookup *, actql_sqlite_database_reply **);
int actql_sqlite_lookup_close_into(actql_control_host *, actql_sqlite_lookup *, actql_sqlite_database_reply **);
/* Release this C alias only. The Database retains unretired child custody;
 * dropping an alias is never a read-stop or old COMMIT ACK. */
int actql_sqlite_lookup_drop(actql_sqlite_lookup **);
#endif
