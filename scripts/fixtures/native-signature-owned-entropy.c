#define _DARWIN_C_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/random.h>
#include "../../src/platform_native/signature/owned_entropy.h"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This diagnostic selects the Darwin arm64 OS entropy implementation.
#endif

static unsigned char *start;
static size_t extent, calls, consumed, fail_call;
static int tracked_entropy(void *output, size_t length) {
  assert(length > 0 && length <= 256);
  assert(output == start + consumed && consumed + length <= extent);
  calls++;
  if (calls == fail_call) { errno = EIO; return -1; }
  int code = getentropy(output, length);
  assert(code == 0);
  consumed += length;
  return code;
}
static void prepare(unsigned char *buffer, size_t length, size_t failure) {
  start = buffer; extent = length; calls = consumed = 0; fail_call = failure;
}
int main(int argc, char **argv) {
  assert(argc == 2);
  unsigned char buffer[4098];
  memset(buffer, 0xa5, sizeof(buffer));
  if (!strcmp(argv[1], "bounded-os")) {
    const size_t lengths[] = {1, 32, 256, 257, 4096};
    for (size_t i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
      const size_t length = lengths[i];
      memset(buffer, 0xa5, sizeof(buffer));
      prepare(buffer + 1, length, 0);
      assert(actql_signature_fill_owned_entropy(buffer + 1, length, tracked_entropy));
      assert(calls == (length + 255) / 256 && consumed == length);
      assert(buffer[0] == 0xa5 && buffer[length + 1] == 0xa5);
    }
  } else if (!strcmp(argv[1], "partial-failure")) {
    for (size_t failure = 1; failure <= 3; ++failure) {
      memset(buffer, 0xa5, sizeof(buffer));
      prepare(buffer + 1, 513, failure);
      assert(!actql_signature_fill_owned_entropy(buffer + 1, 513, tracked_entropy));
      assert(calls == failure && consumed == (failure - 1) * 256);
      for (size_t i = 1; i <= 513; ++i) assert(buffer[i] == 0);
      assert(buffer[0] == 0xa5 && buffer[514] == 0xa5);
    }
  } else if (!strcmp(argv[1], "input-bounds")) {
    prepare(buffer + 1, 4096, 0);
    assert(!actql_signature_fill_owned_entropy(NULL, 32, tracked_entropy));
    assert(!actql_signature_fill_owned_entropy(buffer + 1, 0, tracked_entropy));
    assert(!actql_signature_fill_owned_entropy(buffer + 1, 4097, tracked_entropy));
    assert(!actql_signature_fill_owned_entropy(buffer + 1, 32, NULL));
    assert(calls == 0 && consumed == 0);
    for (size_t i = 0; i < sizeof(buffer); ++i) assert(buffer[i] == 0xa5);
  } else {
    return 2;
  }
  printf("%s: PASS\n", argv[1]);
  return 0;
}
