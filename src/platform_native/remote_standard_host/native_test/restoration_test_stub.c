#include <stdio.h>
#include <stdint.h>

/* Test-owned directories only: interrupt access without changing file identity. */
int32_t actql_test_restoration_rename(const uint8_t *source, const uint8_t *target) {
  return rename((const char *)source, (const char *)target);
}
