// Matching filesystem Owner diagnostic with the real MoonBit memory runtime.
// Private exported facts are not authentication, a grant or a send permit.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include "../../src/platform_native/filesystem/private_file_projection.h"
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

_Noreturn void moonbit_panic(void) { abort(); }
extern void *actql_native_filesystem_open_private_root(moonbit_bytes_t, int32_t);
extern void *actql_native_filesystem_adopt_private_file_projection(void *, moonbit_bytes_t, int32_t);
extern int32_t actql_native_filesystem_private_file_projection_ready(void *);
extern int32_t actql_native_filesystem_export_private_file_projection(void *, moonbit_bytes_t, int32_t);
extern void *actql_native_filesystem_restore_private_file_projection(void *, moonbit_bytes_t, int32_t);

static moonbit_bytes_t bytes(const unsigned char *input, size_t size) {
  moonbit_bytes_t value = moonbit_make_bytes_raw((int32_t)size);
  memcpy(value, input, size);
  return value;
}

int main(int argc, char **argv) {
  assert(argc == 4);
  moonbit_bytes_t path = bytes((const unsigned char *)argv[2], strlen(argv[2]));
  void *root = actql_native_filesystem_open_private_root(path, (int32_t)strlen(argv[2]));
  moonbit_decref(path);
  moonbit_bytes_t material = moonbit_make_bytes_raw(234);
  void *projection;
  int32_t size;
  if (strcmp(argv[1], "adopt") == 0) {
    moonbit_bytes_t name = bytes((const unsigned char *)"bearer", 6);
    projection = actql_native_filesystem_adopt_private_file_projection(root, name, 6);
    moonbit_decref(name);
    assert(actql_native_filesystem_private_file_projection_ready(projection));
    size = actql_native_filesystem_export_private_file_projection(projection, material, 234);
    assert(size == 112);
    int file = open(argv[3], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    assert(file >= 0 && write(file, material, size) == size);
    assert(fsync(file) == 0 && close(file) == 0);
  } else {
    assert(strcmp(argv[1], "restore") == 0);
    int file = open(argv[3], O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    size = file < 0 ? 0 : (int32_t)read(file, material, 234);
    if (file >= 0) assert(close(file) == 0);
    assert(size >= 0);
    projection = actql_native_filesystem_restore_private_file_projection(root, material, size);
    if (!actql_native_filesystem_private_file_projection_ready(projection)) {
      moonbit_decref(projection); moonbit_decref(root); moonbit_decref(material);
      return 3;
    }
    int credential = actql_native_private_file_projection_open(projection);
    assert(credential >= 0);
    char actual[64];
    ssize_t count = read(credential, actual, sizeof(actual));
    assert(count == 14 && memcmp(actual, "fixture-token\n", 14) == 0);
    assert(close(credential) == 0);
    moonbit_bytes_t exported = moonbit_make_bytes_raw(234);
    assert(actql_native_filesystem_export_private_file_projection(projection, exported, 234) == size);
    assert(memcmp(material, exported, size) == 0);
    moonbit_decref(exported);
  }
  moonbit_decref(projection); moonbit_decref(root); moonbit_decref(material);
  return 0;
}
