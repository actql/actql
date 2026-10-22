#ifndef ACTQL_SIGNATURE_OWNED_ENTROPY_H
#define ACTQL_SIGNATURE_OWNED_ENTROPY_H

#include <stdbool.h>
#include <stddef.h>

/* The caller has already checked its original Library/Read and output extent.
 * Each supported OS entropy request is bounded independently; a failed chunk
 * destroys the entire partial result and cannot select another generator. */
static bool actql_signature_fill_owned_entropy(
    unsigned char *output, size_t length, int (*read_entropy)(void *, size_t)) {
  if (!output || !read_entropy || length < 1 || length > 4096) return false;
  size_t offset = 0;
  while (offset < length) {
    size_t chunk = length - offset;
    if (chunk > 256) chunk = 256;
    if (read_entropy(output + offset, chunk) != 0) {
      volatile unsigned char *clear = output;
      for (size_t i = 0; i < length; ++i) clear[i] = 0;
      return false;
    }
    offset += chunk;
  }
  return true;
}

#endif
