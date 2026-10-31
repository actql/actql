#include "moonbit.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Build metadata, never currentness, installation or publication authority.
// The explicit release builder validates its literal with the shared version
// owner. Ordinary diagnostic builds deliberately select no published number.
#ifndef ACTQL_NATIVE_CLIENT_PACKAGE_VERSION
#define ACTQL_NATIVE_CLIENT_PACKAGE_VERSION "0.0.0-development"
#endif
static const char actql_native_package_version[] = ACTQL_NATIVE_CLIENT_PACKAGE_VERSION;
_Static_assert(sizeof(actql_native_package_version) > 1 &&
               sizeof(actql_native_package_version) <= 129,
               "Native package version must fit its initial-control bound");

moonbit_string_t actql_native_client_package_version(void) {
  const int32_t length = (int32_t)sizeof(actql_native_package_version) - 1;
  for (int32_t index = 0; index < length; ++index) {
    unsigned char value = (unsigned char)actql_native_package_version[index];
    if (value < 33 || value > 126) {
      fputs("Invalid compiled Native package version\n", stderr);
      exit(2);
    }
  }
  // One bounded ordinary managed String. Command::new copies its StringView
  // into the same retained initial parser graph and consumes this temporary.
  // This is neither a Read-managed value nor an opaque physical holding.
  moonbit_string_t result = moonbit_make_string_raw(length);
  for (int32_t index = 0; index < length; ++index)
    result[index] = (uint16_t)(unsigned char)actql_native_package_version[index];
  return result;
}
