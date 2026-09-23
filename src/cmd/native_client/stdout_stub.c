#include "moonbit.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int32_t actql_native_client_write_stdout(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return 0;
  if (fwrite(bytes, 1, (size_t)length, stdout) != (size_t)length) return 0;
  return fflush(stdout) == 0;
}

void actql_native_client_fail(moonbit_bytes_t bytes, int32_t length) {
  if (length >= 0) fwrite(bytes, 1, (size_t)length, stderr);
  fputc('\n', stderr);
  fflush(stderr);
  exit(1);
}
