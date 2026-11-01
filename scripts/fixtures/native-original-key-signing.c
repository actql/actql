/* Actual filesystem projection + selected Crypto primitive. These public
 * RFC 8032 fixture keys supply no installed Host/Credential/approval authority. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "moonbit.h"
static void *observed_symbol(void *, const char *);
static int descriptor_closes;
static bool fail_descriptor_close;
static int observed_close(int descriptor) {
  descriptor_closes++;
  if (fail_descriptor_close) {fail_descriptor_close = false;errno = EIO;return -1;}
  return close(descriptor);
}
#define dlsym observed_symbol
#define close observed_close
#include "../../src/platform_native/signature/signature_stub.c"
#undef close
#undef dlsym

extern void *actql_native_filesystem_open_private_root_with_diagnostics(moonbit_bytes_t, int32_t, int32_t);
extern int32_t actql_native_filesystem_root_ready(void *);
extern int32_t actql_native_filesystem_root_close(void *);
extern void *actql_native_filesystem_adopt_private_file_projection(void *, moonbit_bytes_t, int32_t);
extern int32_t actql_native_filesystem_private_file_projection_ready(void *);

static const char *private_key = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIJ1hsZ3v/VpguoRK9JLsLMREScVpezJpGXA7rAMcrn9g\n-----END PRIVATE KEY-----\n";
static const char *selected_private;
static const unsigned char public_key[32] = {0xd7,0x5a,0x98,0x01,0x82,0xb1,0x0a,0xb7,0xd5,0x4b,0xfe,0xd3,0xc9,0x64,0x07,0x3a,0x0e,0xe1,0x72,0xf3,0xda,0xa6,0x23,0x25,0xaf,0x02,0x1a,0x68,0xf7,0x07,0x51,0x1a};
static const char *signature_hex = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b";
static int signatures;
static bool change_during_sign;
static bool pad_to_bound;
static char key_path[4096], old_path[4096];
static int (*real_sign)(EVP_MD_CTX *, unsigned char *, size_t *, const unsigned char *, size_t);

static void write_key(bool oversized) {
  int descriptor = open(key_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
  assert(descriptor >= 0 && fchmod(descriptor, 0600) == 0);
  if (oversized) {
    char bytes[8193];memset(bytes, 'x', sizeof(bytes));
    assert(write(descriptor, bytes, sizeof(bytes)) == (ssize_t)sizeof(bytes));
  } else if (pad_to_bound) {
    char bytes[8192];memset(bytes, ' ', sizeof(bytes));
    memcpy(bytes, selected_private, strlen(selected_private));
    assert(write(descriptor, bytes, sizeof(bytes)) == (ssize_t)sizeof(bytes));
  } else {
    size_t bytes = strlen(selected_private);
    assert(write(descriptor, selected_private, bytes) == (ssize_t)bytes);
  }
  assert(close(descriptor) == 0);
}

static void replace_key(void) {
  assert(rename(key_path, old_path) == 0);
  write_key(false); // Same exact bytes, different actual original generation.
}

static int observed_sign(EVP_MD_CTX *context, unsigned char *output, size_t *length,
                         const unsigned char *message, size_t bytes) {
  signatures++;
  int result = real_sign(context, output, length, message, bytes);
  if (change_during_sign) {change_during_sign = false;replace_key();}
  return result;
}

static void *observed_symbol(void *library, const char *name) {
  void *symbol = dlsym(library, name);
  if (symbol && strcmp(name, "EVP_DigestSign") == 0) {
    memcpy(&real_sign, &symbol, sizeof(symbol));
    return (void *)observed_sign;
  }
  return symbol;
}

static moonbit_bytes_t bytes(const void *source, size_t length) {
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)length);
  if (length) memcpy(result, source, length);
  return result;
}

static void expected_signature(unsigned char output[64]) {
  for (size_t index = 0; index < 64; index++) {
    unsigned value;
    assert(sscanf(signature_hex + 2 * index, "%2x", &value) == 1);
    output[index] = (unsigned char)value;
  }
}

static void *foreign_attempt(void *argument) {
  actql_native_original_key_signing *original = argument;
  assert(actql_native_original_key_signing_once(original) == 10);
  assert(actql_native_original_key_signing_close(original) == 2);
  return NULL;
}

static void *foreign_owner_observation(void *argument) {
  actql_native_original_key_signing *original = argument;
  assert(!actql_native_original_key_signing_owner_current(original));
  return NULL;
}

int main(int argc, char **argv) {
  assert(argc == 4);
  const char *which = argv[1];
  moonbit_bytes_t library_path = bytes(argv[2], strlen(argv[2]));
  actql_native_signature_library *library = actql_native_signature_load_library(
    library_path, (int32_t)strlen(argv[2]), 64);
  moonbit_decref(library_path);
  assert(actql_native_signature_library_ready(library));
  unsigned char expected[64];expected_signature(expected);
  if (strcmp(which, "legacy") == 0) {
    moonbit_bytes_t key = bytes(private_key, strlen(private_key)), message = bytes("", 0);
    moonbit_bytes_t result = actql_native_signature_sign_ed25519(library, key,
      (int32_t)strlen(private_key), message, 0);
    assert(Moonbit_array_length(result) == 65 && result[0] == 0 &&
      memcmp(result + 1, expected, 64) == 0 && signatures == 1);
    moonbit_decref(result);moonbit_decref(key);moonbit_decref(message);
    assert(actql_native_signature_library_close(library) == 0);
    moonbit_decref(library);
    printf("{\"case\":\"legacy\",\"discovered\":1,\"passed\":1,\"failed\":0}\n");
    return 0;
  }
  assert(snprintf(key_path, sizeof(key_path), "%s/key.pem", argv[3]) > 0);
  assert(snprintf(old_path, sizeof(old_path), "%s/original-key.pem", argv[3]) > 0);
  selected_private = private_key;
  if (strcmp(which, "invalid-key") == 0) selected_private = "not a PEM private key";
  if (strcmp(which, "wrong-type") == 0) selected_private = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VuBCIEIJ1hsZ3v/VpguoRK9JLsLMREScVpezJpGXA7rAMcrn9g\n-----END PRIVATE KEY-----\n";
  pad_to_bound = strcmp(which, "bound") == 0;
  write_key(strcmp(which, "oversized") == 0);
  moonbit_bytes_t path = bytes(argv[3], strlen(argv[3]));
  void *root = actql_native_filesystem_open_private_root_with_diagnostics(path,
    (int32_t)strlen(argv[3]), 64);
  moonbit_decref(path);
  assert(actql_native_filesystem_root_ready(root));
  moonbit_bytes_t name = bytes("key.pem", 7);
  actql_native_private_file_projection *key = actql_native_filesystem_adopt_private_file_projection(root, name, 7);
  moonbit_decref(name);
  assert((actql_native_filesystem_private_file_projection_ready(key) != 0) == (strcmp(which, "oversized") != 0));
  moonbit_bytes_t selected_public = bytes(public_key, 32), message = bytes("", 0);
  if (strcmp(which, "wrong-key") == 0) selected_public[0] ^= 1;
  actql_native_original_key_signing *original = actql_native_original_key_signing_prepare(
    library, key, selected_public, 32, message, 0);
  moonbit_decref(selected_public);moonbit_decref(message);
  assert(actql_native_original_key_signing_ready(original) && library->pending_signatures == 1 &&
    original->descriptor == -1 && signatures == 0);
  if (strcmp(which, "orphan-finalize") == 0) {
    // Actual external-object finalization: losing this receiver is not an
    // explicit child ACK to the retained Library. No private read/sign occurs.
    moonbit_decref(original);
    assert(library->pending_signatures == 1 && signatures == 0 && descriptor_closes == 0);
    assert(actql_native_signature_library_close(library) == 1);
    assert(library->pending_signatures == 1);
    assert(actql_native_filesystem_root_close(root) == 0);
    moonbit_decref(key);moonbit_decref(root);moonbit_decref(library);
    puts("{\"case\":\"orphan-finalize\",\"discovered\":1,\"passed\":1,\"failed\":0,\"physicalSignatureCalls\":0,\"pendingLibraryChild\":1}");
    return 0;
  }
  if (strcmp(which, "owner-observation") == 0) {
    assert(actql_native_original_key_signing_owner_current(original));
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_owner_observation, original) == 0);
    assert(pthread_join(thread, NULL) == 0);
    pid_t process = fork();assert(process >= 0);
    if (process == 0) {foreign_owner_observation(original);_exit(0);}
    int status;
    assert(waitpid(process, &status, 0) == process && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(actql_native_original_key_signing_owner_current(original) &&
      !original->attempted && signatures == 0 && descriptor_closes == 0);
    assert(actql_native_original_key_signing_close(original) == 0);
    assert(!actql_native_original_key_signing_owner_current(original));
    assert(actql_native_signature_library_close(library) == 0);
    assert(actql_native_filesystem_root_close(root) == 0);
    moonbit_decref(original);moonbit_decref(key);moonbit_decref(root);moonbit_decref(library);
    puts("{\"case\":\"owner-observation\",\"discovered\":1,\"passed\":1,\"failed\":0,\"physicalSignatureCalls\":0}");
    return 0;
  }
  unsigned char output[64];memset(output, 71, sizeof(output));
  assert(!actql_native_original_key_signing_copy(original, output, 64));
  bool rejected_close = strcmp(which, "replaced-close-unknown") == 0;
  if (strcmp(which, "replaced") == 0 || rejected_close) replace_key();
  if (strcmp(which, "changed-during-sign") == 0) change_during_sign = true;
  bool pending_close = strcmp(which, "close-unknown") == 0 || rejected_close;
  if (pending_close) fail_descriptor_close = true;
  if (strcmp(which, "library-closing") == 0) assert(actql_native_signature_library_close(library) == 1);
  if (strcmp(which, "foreign-thread") == 0) {
    pthread_t thread;assert(pthread_create(&thread, NULL, foreign_attempt, original) == 0);
    assert(pthread_join(thread, NULL) == 0 && signatures == 0 && actql_native_original_key_signing_ready(original));
  }
  if (strcmp(which, "foreign-process") == 0) {
    pid_t process = fork();assert(process >= 0);
    if (process == 0) {foreign_attempt(original);_exit(0);}
    int status;assert(waitpid(process, &status, 0) == process && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(signatures == 0 && actql_native_original_key_signing_ready(original));
  }
  int result = actql_native_original_key_signing_once(original);
  bool success = strcmp(which, "same-key") == 0 || strcmp(which, "bound") == 0 || strcmp(which, "foreign-thread") == 0 || strcmp(which, "foreign-process") == 0;
  if (success) {
    assert(result == 0 && signatures == 1 && descriptor_closes == 1);
    assert(actql_native_original_key_signing_copy(original, output, 64) && memcmp(output, expected, 64) == 0);
  } else if (strcmp(which, "wrong-key") == 0) assert(result == 7 && signatures == 0);
  else if (strcmp(which, "invalid-key") == 0) assert(result == 3 && signatures == 0);
  else if (strcmp(which, "wrong-type") == 0) assert(result == 4 && signatures == 0);
  else if (strcmp(which, "replaced") == 0 || strcmp(which, "oversized") == 0) assert(result == 6 && signatures == 0);
  else if (strcmp(which, "changed-during-sign") == 0) assert(result == 6 && signatures == 1);
  else if (strcmp(which, "library-closing") == 0) assert(result == 10 && signatures == 0 && descriptor_closes == 0);
  else assert(pending_close && result == 9 && signatures == (rejected_close ? 0 : 1) && descriptor_closes == 1);
  assert(actql_native_original_key_signing_once(original) == 8);
  assert(signatures == (success || strcmp(which, "changed-during-sign") == 0 || strcmp(which, "close-unknown") == 0 ? 1 : 0));
  if (!success) assert(!actql_native_original_key_signing_copy(original, output, 64));
  if (pending_close) {
    assert(actql_native_original_key_signing_primary(original) == (rejected_close ? 6 : 0));
    assert(actql_native_original_key_signing_close(original) == 1 &&
      actql_native_original_key_signing_close(original) == 1 && descriptor_closes == 1);
    assert(actql_native_signature_library_close(library) == 1);
    // Fixture-only OS cleanup does not repair the original consumed/unknown
    // close, remove its child or manufacture a returned operation/Library ACK.
    assert(close(original->descriptor) == 0);
    assert(actql_native_original_key_signing_close(original) == 1 && library->pending_signatures == 1);
    assert(actql_native_filesystem_root_close(root) == 0);
  } else {
    assert(actql_native_original_key_signing_close(original) == 0 && library->pending_signatures == 0);
    assert(actql_native_original_key_signing_close(original) == 0);
    assert(actql_native_signature_library_close(library) == 0);
    assert(actql_native_filesystem_root_close(root) == 0);
    moonbit_decref(original);moonbit_decref(key);moonbit_decref(root);moonbit_decref(library);
  }
  printf("{\"case\":\"%s\",\"discovered\":1,\"passed\":1,\"failed\":0,\"physicalSignatureCalls\":%d,\"pendingUnknownCloseRetained\":%s}\n",
    which, signatures, pending_close ? "true" : "false");
  return 0;
}
