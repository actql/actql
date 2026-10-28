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
/* Preserve even a rejected partial acquisition on the caller's existing
 * receiver. Start with *descriptor == -1; any returned descriptor needs its
 * actual close, regardless of the generation-match result. */
bool actql_native_private_file_projection_open_with_custody(
  actql_native_private_file_projection *projection, int *descriptor
);
bool actql_native_private_file_projection_matches(
  actql_native_private_file_projection *projection,
  int descriptor
);

#endif
