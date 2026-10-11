#ifndef ACTQL_NATIVE_PRIVATE_FILE_PROJECTION_H
#define ACTQL_NATIVE_PRIVATE_FILE_PROJECTION_H

#include <stdbool.h>

// The filesystem Owner retains the original private root and installation
// facts. No caller-provided generation, path or public identity replaces them.
typedef struct actql_native_private_file_projection
  actql_native_private_file_projection;

// The caller owns the returned descriptor and must close it on every path.
// These hooks do not grant permission, renew custody or reopen an unknown use.
int actql_native_private_file_projection_open(
  actql_native_private_file_projection *projection
);
bool actql_native_private_file_projection_matches(
  actql_native_private_file_projection *projection,
  int descriptor
);

#endif
