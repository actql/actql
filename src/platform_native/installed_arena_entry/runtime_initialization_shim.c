#include "runtime_initialization_shim.h"
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
#include "../host_bootstrap/python_initial_platform.h"
#endif

/* This is the same emitted main renamed by the existing private producer.
 * No function supplied by a caller or alternate initializer is accepted. */
extern int actql_original_control_initialize(int argc, char **argv);

struct actql_control_runtime_origin {
    pid_t process;
    pthread_t thread;
};
static struct actql_control_runtime_origin origin;
/* 0 untouched, 1 initializing/unconfirmed, 2 returned successfully, 3 failed.
 * No phase represents physical retirement and no transition returns to zero. */
static _Atomic int phase;

int actql_control_runtime_initialize_into(actql_control_runtime_origin **slot) {
    if (slot == NULL || *slot != NULL) return ACTQL_CONTROL_INVALID_SLOT;
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
    /* The selected Python link has no automatic MI initializer. Its original
     * physical entrance must already be current before any Moon initializer.
     * Missing/partial/restored supply does not consume the Runtime attempt. */
    if (!actql_native_python_initial_managed_current())
        return ACTQL_CONTROL_UNAVAILABLE;
#endif
    /* An old direct initializer or partial registration is not a fresh
     * component and cannot be silently adopted or initialized a second time. */
    if (actql_control_runtime_roots_state() != 0) return ACTQL_CONTROL_UNAVAILABLE;
    int untouched = 0;
    if (!atomic_compare_exchange_strong_explicit(&phase, &untouched, 1,
            memory_order_acq_rel, memory_order_acquire))
        return ACTQL_CONTROL_UNAVAILABLE;
    origin.process = getpid();
    origin.thread = pthread_self();
    *slot = &origin;
    char name[] = "actql-private-compiler-control";
    char *arguments[] = {name, NULL};
    int result = actql_original_control_initialize(1, arguments);
    int ready = result == 0 && actql_control_runtime_roots_state() == 1;
    atomic_store_explicit(&phase, ready ? 2 : 3, memory_order_release);
    return ready ? ACTQL_CONTROL_OK : ACTQL_CONTROL_CLEANUP_PENDING;
}

int actql_control_runtime_current(actql_control_runtime_origin *original) {
    /* Check identity before dereferencing any pointer supplied by a caller. */
    if (original != &origin ||
        atomic_load_explicit(&phase, memory_order_acquire) != 2)
        return ACTQL_CONTROL_UNAVAILABLE;
    if (origin.process != getpid() || !pthread_equal(origin.thread, pthread_self()))
        return ACTQL_CONTROL_UNAVAILABLE;
#if defined(ACTQL_PYTHON_INITIAL_OPERATIONAL_ENTRY)
    if (!actql_native_python_initial_managed_current())
        return ACTQL_CONTROL_UNAVAILABLE;
#endif
    return ACTQL_CONTROL_OK;
}
