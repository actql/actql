#include "moonbit.h"
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
