/* The selected installer compiles one immutable command recipe and source pin.
 * This private entry is an actual physical caller, not a Run/Account issuer.
 * Ordinary unselected builds refuse before argv copying or command parsing. */
#include "moonbit.h"
#include "initial_control_capture.h"
#include <errno.h>
typedef struct { resident_entry *entry; } resident_entry_handle;
static void keep_entry_custody(void *handle) { (void)handle; }

MOONBIT_FFI_EXPORT void *actql_resident_capture_initial_entry(void) {
    bool first = !original_entry.attempted;
    (void)capture_entry(&original_entry);
    resident_entry_handle *handle = moonbit_make_external_object(
        keep_entry_custody, sizeof(*handle));
    /* Retain the SAME first partial capture even when its precondition
     * refused. A second call never receives that original or renews entry. */
    handle->entry = first ? &original_entry : NULL;
    return handle;
}

MOONBIT_FFI_EXPORT int32_t actql_resident_initial_entry_current(resident_entry_handle *handle) {
    return handle && entry_current(handle->entry) ? 1 : 0;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t actql_resident_initial_entry_pin(
        resident_entry_handle *handle, int32_t kind) {
    if (!handle || !entry_current(handle->entry)) return moonbit_make_bytes(0, 0);
#ifdef ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
    const char *pin = kind == 0 ? ACTQL_RESIDENT_SOURCE_SHA : ACTQL_RESIDENT_RECIPE_SHA;
    int bytes = kind == 0 ? 40 : 32;
    moonbit_bytes_t result = moonbit_make_bytes(bytes, 0);
    for (int i = 0; i < bytes; ++i) {
        if (kind == 0) result[i] = (unsigned char)pin[i];
        else {
            unsigned char a = (unsigned char)pin[2*i], b = (unsigned char)pin[2*i+1];
            result[i] = (unsigned char)(((a <= '9' ? a-'0' : a-'a'+10) << 4) |
                (b <= '9' ? b-'0' : b-'a'+10));
        }
    }
    return result;
#else
    (void)kind;
    return moonbit_make_bytes(0, 0);
#endif
}

MOONBIT_FFI_EXPORT int64_t actql_resident_initial_entry_quantity(
        resident_entry_handle *handle, int32_t kind) {
    if (!handle || !entry_current(handle->entry)) return -1;
#ifdef ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
    static const int64_t quantities[] = {
        ACTQL_RESIDENT_GENERATION, ACTQL_RESIDENT_CAPACITY,
        ACTQL_RESIDENT_CONTROL_ENVELOPE, ACTQL_RESIDENT_PLANNING_WORK,
        ACTQL_RESIDENT_ATTEMPTS, ACTQL_RESIDENT_HOLDINGS
    };
    if (kind >= 0 && (size_t)kind < sizeof(quantities)/sizeof(quantities[0])) return quantities[kind];
#ifdef ACTQL_RESIDENT_SQLITE_HEAP
    static const int64_t component_quantities[] = {
        ACTQL_RESIDENT_SQLITE_HEAP, ACTQL_RESIDENT_CRYPTO_HEAP,
        ACTQL_RESIDENT_DIAGNOSTIC_BYTES
    };
    if (kind >= 6 && (size_t)(kind - 6) < sizeof(component_quantities)/sizeof(component_quantities[0]))
        return component_quantities[kind - 6];
#endif
#else
    (void)kind;
#endif
    return -1;
}

/* Only after the original bootstrap reports actual complete retirement, or
 * the initial precondition refused before bootstrap acquisition. This latches
 * command-entry retirement, not Site/Run/child/FD cleanup or stop. */
MOONBIT_FFI_EXPORT int32_t actql_resident_retire_initial_entry(resident_entry_handle *handle) {
    if (!handle || handle->entry != &original_entry || !handle->entry->attempted ||
        handle->entry->retired) return 0;
#if defined(__APPLE__)
    /* Normal argv/image/loader currentness must not block same-original cleanup. */
    if (handle->entry->process != getpid() || !pthread_main_np() ||
        !pthread_equal(handle->entry->thread, pthread_self())) return 0;
#else
    return 0;
#endif
    handle->entry->retired = true;
    return 1;
}

MOONBIT_FFI_EXPORT void actql_resident_initial_control_diagnostic(int32_t stage) {
    fprintf(stderr, "actql-native-remote-resident-site: initial control refused at stage %d\n", stage);
}
/* Consume the SAME managed diagnostic while its original Read is entered.
 * This is stderr output only, never a cleanup or operation acknowledgment. */
MOONBIT_FFI_EXPORT void actql_resident_command_failure(moonbit_bytes_t message, int32_t length) {
    if (length < 0) return;
    fwrite(message, 1, (size_t)length, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}
MOONBIT_FFI_EXPORT void actql_resident_initial_control_exit_failure(void) { exit(1); }

/* Called after the same entry's explicit bootstrap retirement. This describes
 * only the original command, not a remote Run/holding/publication release.
 * Use fixed bytes after its managed Read has closed; no managed allocation. */
MOONBIT_FFI_EXPORT int32_t actql_resident_controller_retired(resident_entry_handle *handle) {
#if defined(__APPLE__)
    if (!handle || handle->entry != &original_entry || !handle->entry->retired ||
        handle->entry->process != getpid() || !pthread_main_np() ||
        !pthread_equal(handle->entry->thread, pthread_self())) return -1;
    static const char message[] = "{\"kind\":\"stopped\",\"scope\":\"original-command-retired\"}\n";
    size_t sent = 0;
    while (sent < sizeof(message) - 1) {
        ssize_t result = write(STDOUT_FILENO, message + sent, sizeof(message) - 1 - sent);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) return -1;
        sent += (size_t)result;
    }
    return 0;
#else
    (void)handle;
    return -1;
#endif
}
