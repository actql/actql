/* Actual command FFI with the pinned MoonBit initial-control runtime. This
 * component creates no bootstrap mapping, Site, Store, Run or permission. */
#include "../../src/cmd/native_remote_resident_site/initial_control_stub.c"
#include <assert.h>

int main(int argc, char **argv) {
    assert(argc == 2);
    if (strcmp(argv[1], "stderr") == 0) {
        const char text[] = "command diagnostic";
        moonbit_bytes_t message = moonbit_make_bytes(sizeof(text)-1, 0);
        memcpy(message, text, sizeof(text)-1);
        actql_resident_command_failure(message, sizeof(text)-1);
        moonbit_decref(message);
        puts("PASS diagnostic consumed on stderr only");
        return 0;
    }
    bool partial = strcmp(argv[1], "partial") == 0;
#if defined(__linux__)
    const char *loader_key = "LD_ACTQL_RESIDENT_COMPONENT";
#else
    const char *loader_key = "DYLD_ACTQL_RESIDENT_COMPONENT";
#endif
    if (partial) assert(setenv(loader_key, "1", 1) == 0);
    resident_entry_handle *original = actql_resident_capture_initial_entry();
#ifdef ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
    assert(actql_resident_initial_entry_current(original) == (partial ? 0 : 1));
    if (!partial && strcmp(argv[1], "components") == 0) {
        assert(actql_resident_initial_entry_quantity(original, 6) == ACTQL_RESIDENT_SQLITE_HEAP);
        assert(actql_resident_initial_entry_quantity(original, 7) == ACTQL_RESIDENT_CRYPTO_HEAP);
        assert(actql_resident_initial_entry_quantity(original, 8) == ACTQL_RESIDENT_DIAGNOSTIC_BYTES);
    }
#else
    assert(actql_resident_initial_entry_current(original) == 0);
#endif
    resident_entry_handle *second = actql_resident_capture_initial_entry();
    assert(actql_resident_initial_entry_current(second) == 0);
    assert(actql_resident_controller_retired(original) == -1);
    assert(actql_resident_controller_retired(second) == -1);
    assert(actql_resident_retire_initial_entry(second) == 0);
    assert(actql_resident_retire_initial_entry(original) == 1);
    assert(actql_resident_initial_entry_current(original) == 0);
    assert(actql_resident_retire_initial_entry(original) == 0);
    assert(actql_resident_controller_retired(original) == 0);
    assert(actql_resident_controller_retired(second) == -1);
    if (partial) assert(unsetenv(loader_key) == 0);
    assert(actql_resident_initial_entry_current(original) == 0);
    moonbit_decref(second);
    moonbit_decref(original);
    puts("PASS original capture retirement; no second entry or renewal");
    return 0;
}
