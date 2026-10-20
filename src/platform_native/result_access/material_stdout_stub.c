#include "moonbit.h"
#include <stdint.h>
#include <stdio.h>

/* This writes the separately authorized table, never the material read bytes.
 * A partial write or lost flush acknowledgement is not retried or successful. */
int32_t actql_native_result_material_write_table(moonbit_bytes_t bytes,
                                                int32_t length) {
  if (length < 0) return -3;
  if (fwrite(bytes, 1, (size_t)length, stdout) != (size_t)length) return -1;
  if (fflush(stdout) != 0) return -2;
  return 0;
}
