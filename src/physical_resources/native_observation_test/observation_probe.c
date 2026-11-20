/* Test-local strong sink. It links the real Resource bridge without importing
 * filesystem/CLI or creating any production observation root/registry. */
#include <stdint.h>
static const void *original;
static int64_t last_execution = -1;
void actql_test_capacity_probe_begin(const void *ledger) {
  original = ledger;
  last_execution = -1;
}
void actql_test_capacity_probe_end(void) { original = 0; }
int64_t actql_test_capacity_probe_execution(void) { return last_execution; }
void actql_native_file_capacity_observe(const void *ledger, int32_t kind,
    int32_t serial, int64_t requested, int64_t capacity, int64_t limit,
    int64_t reserved) {
  (void)serial; (void)requested; (void)limit; (void)reserved;
  if (original && ledger == original && kind == 4) last_execution = capacity;
}
