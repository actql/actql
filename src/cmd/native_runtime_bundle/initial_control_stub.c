/* Compile the existing capture implementation into THIS installer image.
 * Its process-lived original and MoonBit external handle belong only to this
 * command; no Resident handle or resource crosses the executable boundary. */
#if defined(__linux__) && defined(__x86_64__) && defined(ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY)
#include "initial_control_capture_linux_x64.h"
#define ACTQL_BUNDLE_ENTRY_CLEANUP_CURRENT(entry) bundle_linux_cleanup_current(entry)
#endif
#ifdef ACTQL_BUNDLE_INITIAL_CONTROL_HEADER
#define ACTQL_RESIDENT_INITIAL_CONTROL_HEADER ACTQL_BUNDLE_INITIAL_CONTROL_HEADER
#endif
#define actql_resident_capture_initial_entry actql_bundle_capture_initial_entry
#define actql_resident_initial_entry_current actql_bundle_initial_entry_current
#define actql_resident_initial_entry_pin actql_bundle_initial_entry_pin
#define actql_resident_initial_entry_quantity actql_bundle_base_entry_quantity
#define actql_resident_retire_initial_entry actql_bundle_retire_initial_entry
#define actql_resident_initial_control_diagnostic actql_bundle_capture_diagnostic_unused
#define actql_resident_command_failure actql_bundle_command_failure
#define actql_resident_initial_control_exit_failure actql_bundle_initial_control_exit_failure
#include "../native_remote_resident_site/initial_control_stub.c"
MOONBIT_FFI_EXPORT void actql_bundle_initial_control_diagnostic(int32_t stage) {
    fprintf(stderr, "actql-native-runtime-bundle: initial control refused at stage %d\n", stage);
}

/* These are selected extents/ceilings inside the SAME already acquired arena,
 * never a second backing grant. The MoonBit caller checks coexistence using
 * the actual provider layout before entering the managed command domain. */
MOONBIT_FFI_EXPORT int64_t actql_bundle_initial_entry_quantity(
        resident_entry_handle *handle, int32_t kind) {
    if (kind < 6) return actql_bundle_base_entry_quantity(handle, kind);
    if (!handle || !entry_current(handle->entry)) return -1;
#ifdef ACTQL_BUNDLE_INITIAL_CONTROL_HEADER
    static const int64_t quantities[] = {
        ACTQL_BUNDLE_MANAGED_PAYLOAD, ACTQL_BUNDLE_SQLITE_HEAP,
        ACTQL_BUNDLE_CRYPTO_HEAP, ACTQL_BUNDLE_DIAGNOSTIC_BYTES
    };
    if (kind >= 6 && (size_t)(kind - 6) < sizeof(quantities)/sizeof(quantities[0]))
        return quantities[kind - 6];
#endif
    return -1;
}
