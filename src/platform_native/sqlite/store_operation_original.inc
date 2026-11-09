#include "store_operation_original.h"
#include <pthread.h>

struct actql_native_store_operation {
  actql_native_sqlite_library *library;
  void *receiver;
  actql_native_store_operation_route route;
  actql_native_store_delivery_construction delivery_construction;
  pid_t process;
  pthread_t thread;
  void *bound_database;
  bool open_attempted, binding_attempted, database_closed;
  bool attempted, activated, flight, sql, sql_ready, cleanup, cleanup_ready, cleanup_only, failed, closed, calling, callback_failed;
  int32_t primary_code, cleanup_code, callback_code;
};

/* No finalizer invokes callbacks, changes a physical scope or manufactures an
 * ACK. The original coordinator and Database retain their existing duties. */
static void actql_store_operation_finalize(void *pointer) {
  actql_native_store_operation *value = pointer;
  if (value->receiver != NULL) moonbit_decref(value->receiver);
  if (value->library != NULL) moonbit_decref(value->library);
}
static bool actql_store_operation_thread(actql_native_store_operation *value) {
  return value != NULL && value->process == getpid() &&
    pthread_equal(value->thread, pthread_self());
}
static int32_t actql_store_operation_failed(
    actql_native_store_operation *value, int32_t code) {
  if (code == 0) code = -1;
  if (value->calling) {
    value->callback_failed = true;
    if (value->callback_code == 0) value->callback_code = code;
  }
  if (value->primary_code == 0) value->primary_code = code;
  else if (value->cleanup_code == 0) value->cleanup_code = code;
  value->failed = true;
  return code;
}
static int32_t actql_store_operation_route(
    actql_native_store_operation *value, int32_t tag) {
  if (!actql_store_operation_thread(value) || value->closed ||
      value->receiver == NULL || value->route == NULL) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  /* Observe failures newly latched by THIS callback, independently of a
   * previous failure under which legitimate cleanup is still permitted. */
  value->callback_failed = false;
  value->callback_code = 0;
  value->calling = true;
  /* The selected generated FuncRef trampoline borrows its parameters, as do
   * the existing Native coordinator roots. The retained fields keep them live
   * throughout this guarded call; per-call increfs would leak child aliases. */
  int32_t code = value->route(value->receiver, value->library, tag);
  value->calling = false;
  if (code != 0) return actql_store_operation_failed(value, code);
  if (value->callback_failed) return value->callback_code;
  return 0;
}
MOONBIT_FFI_EXPORT void *actql_native_sqlite_prepare_store_operation(
    void *library, void *receiver, actql_native_store_operation_route route) {
  actql_native_store_operation *value = moonbit_make_external_object(
    actql_store_operation_finalize, sizeof(*value));
  memset(value, 0, sizeof(*value));
  value->library = library;
  value->receiver = receiver;
  value->route = route;
  value->process = getpid();
  value->thread = pthread_self();
  if (library != NULL) moonbit_incref(library);
  if (receiver != NULL) moonbit_incref(receiver);
  /* Return original partial custody BEFORE any callback or physical call. */
  return value;
}
/* Same retained receiver/Library, with one closed constructor purpose. The
 * original three-argument entrance remains unchanged for existing callers. */
MOONBIT_FFI_EXPORT void *actql_native_sqlite_prepare_store_operation_with_delivery_construction(
    void *library, void *receiver, actql_native_store_operation_route route,
    actql_native_store_delivery_construction construction) {
  actql_native_store_operation *value =
    actql_native_sqlite_prepare_store_operation(library, receiver, route);
  value->delivery_construction = construction;
  return value;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_prepare_delivery_window(
    actql_native_store_operation *value, int32_t target) {
  if (!actql_store_operation_thread(value) || value->closed ||
      !value->activated || value->failed || value->cleanup_only ||
      !value->flight || value->sql || value->cleanup ||
      value->receiver == NULL || value->delivery_construction == NULL ||
      target < 1 || target > 16777216) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  value->callback_failed = false;
  value->callback_code = 0;
  value->calling = true;
  int32_t code = value->delivery_construction(value->receiver, value->library, target);
  value->calling = false;
  if (code != 0) return actql_store_operation_failed(value, code);
  if (value->callback_failed) return value->callback_code;
  return 0;
}
/* Constructor custody is immutable after preparation. Legacy routing retains
 * its one-row path only inside the same valid normal Read flight; an invalid
 * or failed funded original cannot select that compatibility path. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_delivery_constructor(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed ||
      !value->activated || value->failed || value->cleanup_only ||
      !value->flight || value->sql || value->cleanup || value->calling ||
      value->receiver == NULL || value->route == NULL) return -1;
  return value->delivery_construction == NULL ? 0 : 1;
}
/* Separate generated test signature: the compiler emits one typed C
 * declaration per imported symbol. Both finite callers use the SAME original
 * bridge; no callback/layout cast or alternate acquisition is introduced. */
MOONBIT_FFI_EXPORT void *actql_native_sqlite_test_prepare_store_wal_operation(
    void *library, void *receiver, actql_native_store_operation_route route) {
  return actql_native_sqlite_prepare_store_operation(library, receiver, route);
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_activate(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (value->attempted) return -1;
  value->attempted = true;
  if (value->library == NULL || !value->library->selected_component ||
      value->library->selected_process != getpid())
    return actql_store_operation_failed(value, -3);
  int32_t code = actql_store_operation_route(value, -1);
  if (code == 0 && !value->failed) value->activated = true;
  return value->activated ? 0 : code == 0 ? -1 : code;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_enter(
    actql_native_store_operation *value, int32_t cleanup) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (!value->activated) return -1;
  if (cleanup != 0 && cleanup != 1) return -1;
  if (!cleanup && (value->failed || value->cleanup_only || value->flight || value->sql)) return -1;
  /* Cleanup may recover the SAME failed flight only after its coordinator
   * confirms the actual old leave and entry; a missing ACK changes no latch. */
  if (cleanup && value->cleanup_ready && value->flight &&
      !(value->failed && value->sql)) return -1;
  /* A failed SQL switch inside cleanup retains its attempted SQL flight.
   * The SAME coordinator's cleanup callback must reconcile that physical
   * switch before any SQL latch is cleared. Healthy duplicate entry refuses. */
  /* An attempted switch remains outstanding even if its reply is lost. */
  value->flight = true;
  if (cleanup) {
    /* Cleanup selection spends normal use even when its callback succeeds
     * without latching an error. A return ACK ends a flight, not this history. */
    value->cleanup_only = true;
    value->cleanup = true;
    value->cleanup_ready = false;
  }
  int32_t code = actql_store_operation_route(value, cleanup ? 4 : 0);
  if (code == 0) {
    value->flight = true;
    value->sql = false;
    value->sql_ready = false;
    value->cleanup = cleanup != 0;
    value->cleanup_ready = cleanup != 0;
  }
  return code;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_leave(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (!value->flight || value->sql) return -1;
  if (value->failed && !value->cleanup) return -1;
  if (value->cleanup && !value->cleanup_ready) return -1;
  int32_t code = actql_store_operation_route(value, 3);
  if (code == 0) { value->flight = false; value->cleanup = false; value->cleanup_ready = false; }
  return code;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_close(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value)) return -1;
  if (value->closed) return 0;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (value->flight || value->sql ||
      (value->binding_attempted && !value->database_closed)) return -1;
  value->closed = true;
  /* Metadata retirement is not Database/Store/Library/parent retirement. */
  if (value->receiver != NULL) {
    moonbit_decref(value->receiver); value->receiver = NULL;
  }
  return 0;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_primary(
    actql_native_store_operation *value) {
  return actql_store_operation_thread(value) ? value->primary_code : -1;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_cleanup(
    actql_native_store_operation *value) {
  return actql_store_operation_thread(value) ? value->cleanup_code : -1;
}


static int32_t actql_store_operation_enter_sql(
    actql_native_store_operation *value, int32_t cleanup_allowed) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (!value->activated || !value->flight || value->sql) return -1;
  if ((value->failed && !value->cleanup) ||
      (value->cleanup && (!value->cleanup_ready || !cleanup_allowed))) return -1;
  value->sql = true; /* Attempted scope, retained until its actual return ACK. */
  value->sql_ready = false;
  int32_t code = actql_store_operation_route(value, 1);
  if (code == 0 && !actql_library_available(value->library))
    return actql_store_operation_failed(value, -4);
  if (code == 0) value->sql_ready = true;
  return code;
}
static int32_t actql_store_operation_leave_sql(actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  if (value->calling) return actql_store_operation_failed(value, -2);
  if (!value->flight || !value->sql || !value->sql_ready) return -1;
  int32_t code = actql_store_operation_route(value, 2);
  if (code == 0) { value->sql = false; value->sql_ready = false; }
  return code;
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_enter_store_sql(
    actql_native_sqlite_database *database, int32_t cleanup_allowed) {
  if (database == NULL) return 0;
  actql_native_store_operation *value = database->store_operation;
  if (value == NULL) return 0; /* Preserve the unselected original entrance. */
  if (value->bound_database != database || value->library != database->library)
    return -1;
  return actql_store_operation_enter_sql(value, cleanup_allowed);
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_leave_store_sql(
    actql_native_sqlite_database *database) {
  if (database == NULL) return 0;
  actql_native_store_operation *value = database->store_operation;
  if (value == NULL) return 0;
  if (value->bound_database != database || value->library != database->library)
    return -1;
  return actql_store_operation_leave_sql(value);
}

MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_finish_open(
    actql_native_store_operation *value) {
  return actql_store_operation_leave_sql(value);
}
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_has_store_operation(
    actql_native_sqlite_database *database) {
  return database != NULL && database->store_operation != NULL;
}
/* The cleanup writer must present the exact original already bound to this
 * Database. This observation grants no new flight or scope; SQL entry below
 * still requires the original coordinator's actual cleanup/current frame. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_matches_store_operation(
    actql_native_sqlite_database *database,
    actql_native_store_operation *original) {
  return database != NULL && actql_store_operation_thread(original) &&
    !original->closed && database->store_operation == original &&
    original->bound_database == database &&
    original->library == database->library;
}
/* Attach an already-open SAME Journal to its fixed original coordinator.
 * This is a pure reference association while Read is entered, not a Database
 * open, SQL scope, current callback, permission or physical retirement ACK. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_bind_database_store_operation(
    actql_native_sqlite_database *database,
    actql_native_store_operation *original) {
  if (!actql_store_operation_thread(original) || original->closed) return -1;
  if (original->calling) return actql_store_operation_failed(original, -2);
  if (!original->activated || !original->flight || original->sql ||
      original->cleanup || original->cleanup_only || original->failed ||
      original->open_attempted || original->binding_attempted ||
      original->bound_database != NULL || database == NULL ||
      database->process != getpid() || !database->opened ||
      database->database == NULL || database->checked_close_ack ||
      database->store_operation != NULL ||
      original->library != database->library) return -1;
  original->binding_attempted = true;
  original->bound_database = database;
  database->store_operation = original;
  moonbit_incref(original);
  return 0;
}
MOONBIT_FFI_EXPORT void actql_native_sqlite_database_fence_original_store(
    actql_native_sqlite_database *database) {
  if (database == NULL) return;
  actql_native_store_operation *value = database->store_operation;
  if (actql_store_operation_thread(value) && value->bound_database == database &&
      value->library == database->library) database->transaction_fenced = 1;
}

/* Existing cleanup work uses normal current scope before cleanup is selected.
 * Both a retained failure and successful cleanup selection keep the SAME
 * original cleanup-only route; no fabricated error is needed to retain it. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_enter_recovery(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  return actql_native_sqlite_store_operation_enter(value,
    value->failed || value->cleanup_only ? 1 : 0);
}
