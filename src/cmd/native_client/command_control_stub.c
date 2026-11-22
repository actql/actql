#include "moonbit.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// The caller invokes this only after successfully leaving its original Read.
// Preserve exact UTF-16 DATA in caller control storage; this is neither a
// physical cleanup acknowledgement nor a copy of an opaque failure receiver.
moonbit_string_t actql_native_client_copy_command_control_text(
    moonbit_string_t original) {
  int32_t length = Moonbit_array_length(original);
  moonbit_string_t copy = moonbit_make_string_raw(length);
  memcpy(copy, original, (size_t)length * sizeof(uint16_t));
  return copy;
}

// This is the same compiler selection as the Native HTTP allocator. A missing
// installer original in a scoped binary must never select stock transport.
bool actql_native_remote_http_requires_original(void) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  return true;
#else
  return false;
#endif
}

// Copy only the bounded response DATA after the original Read has left.
moonbit_bytes_t actql_native_remote_http_copy_body(moonbit_bytes_t original) {
  int32_t length = Moonbit_array_length(original);
  moonbit_bytes_t copy = moonbit_make_bytes_raw(length);
  memcpy(copy, original, (size_t)length);
  return copy;
}
