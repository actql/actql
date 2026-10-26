/* Same Library's physical signing child, not a Credential or approval Owner.
 * The Host must confirm its exact original use before sign_once. No key bytes
 * cross into managed values, and no pathname/stat substitute is accepted. */
#include "../filesystem/private_file_projection.h"

typedef struct {
  actql_native_signature_library *library;
  actql_native_private_file_projection *key;
  moonbit_bytes_t message;
  int32_t message_length;
  unsigned char expected_public_key[32];
  unsigned char signature[ACTQL_ED25519_SIGNATURE_BYTES];
  pid_t process;
  pthread_t thread;
  int descriptor;
  int primary_status;
  bool child_registered;
  bool attempted;
  bool descriptor_close_consumed;
  bool descriptor_unconfirmed;
  bool closed;
} actql_native_original_key_signing;

static bool actql_original_key_signing_owner(
  const actql_native_original_key_signing *original
) {
  return original && original->process == getpid() &&
    pthread_equal(original->thread, pthread_self());
}

static bool actql_original_key_signing_close_descriptor(
  actql_native_original_key_signing *original
) {
  if (original->descriptor_unconfirmed) return false;
  if (original->descriptor < 0) return true;
  if (original->descriptor_close_consumed) return false;
  original->descriptor_close_consumed = true;
  if (close(original->descriptor) != 0) {
    original->descriptor_unconfirmed = true;
    return false;
  }
  original->descriptor = -1;
  return true;
}

static int32_t actql_original_key_signing_retire(
  actql_native_original_key_signing *original, bool acknowledge
) {
  if (!actql_original_key_signing_owner(original)) return 2;
  if (original->closed) return 0;
  if (!actql_original_key_signing_close_descriptor(original)) return 1;
  original->closed = true;
  memset(original->signature, 0, sizeof(original->signature));
  if (original->key) {moonbit_decref(original->key);original->key = NULL;}
  if (original->message) {moonbit_decref(original->message);original->message = NULL;}
  if (original->child_registered) {
    if (acknowledge) original->library->pending_signatures--;
    original->child_registered = false;
    moonbit_decref(original->library);
    original->library = NULL;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_original_key_signing_close(
  actql_native_original_key_signing *original
) {
  return actql_original_key_signing_retire(original, true);
}

static void actql_original_key_signing_finalize(void *value) {
  /* Best-effort cleanup is not a returned ACK. An uncertain close is never
   * retried; the caller must retain that original pending receiver. */
  (void)actql_original_key_signing_retire(value, false);
}

MOONBIT_FFI_EXPORT
void *actql_native_original_key_signing_prepare(
  actql_native_signature_library *library,
  actql_native_private_file_projection *key,
  moonbit_bytes_t public_key, int32_t public_length,
  moonbit_bytes_t message, int32_t message_length
) {
  actql_native_original_key_signing *original = moonbit_make_external_object(
    actql_original_key_signing_finalize, sizeof(*original));
  memset(original, 0, sizeof(*original));
  original->process = getpid();
  original->thread = pthread_self();
  original->descriptor = -1;
  original->primary_status = 2;
  if (!library || !key || !public_key || !message || public_length != 32 ||
      message_length < 0 || message_length > 1048576 ||
      !actql_signature_library_available(library) ||
      library->pending_signatures == UINT32_MAX) return original;
  original->library = library;
  original->key = key;
  original->message = message;
  original->message_length = message_length;
  memcpy(original->expected_public_key, public_key, 32);
  moonbit_incref(library);
  moonbit_incref(key);
  moonbit_incref(message);
  library->pending_signatures++;
  original->child_registered = true;
  original->primary_status = -1;
  return original;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_original_key_signing_ready(
  actql_native_original_key_signing *original
) {
  return actql_original_key_signing_owner(original) && !original->closed &&
    original->child_registered && !original->attempted;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_original_key_signing_primary(
  actql_native_original_key_signing *original
) {
  return actql_original_key_signing_owner(original) ? original->primary_status : 10;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_original_key_signing_once(
  actql_native_original_key_signing *original
) {
  if (!actql_original_key_signing_owner(original) || original->closed ||
      !original->child_registered) return 10;
  if (original->attempted) return 8;
  // Spend before the first physical/current observation or fallible key work.
  original->attempted = true;
  original->primary_status = 10;
  actql_native_signature_library *library = original->library;
  if (!actql_signature_library_available(library)) return 10;
  if (!actql_native_private_file_projection_open_with_custody(original->key, &original->descriptor)) {
    original->primary_status = 6;
    return actql_original_key_signing_close_descriptor(original) ? 6 : 9;
  }
  struct stat status;
  unsigned char *secret = NULL;
  size_t size = 0;
  int result = 6;
  if (fstat(original->descriptor, &status) != 0 || !S_ISREG(status.st_mode) ||
      status.st_size <= 0 || status.st_size > 8192) goto done;
  size = (size_t)status.st_size;
  secret = actql_signature_allocate(library, size + 1);
  if (secret == NULL) {result = 5;goto done;}
  size_t used = 0;
  while (used <= size) {
    ssize_t count = read(original->descriptor, secret + used, size + 1 - used);
    if (count < 0) goto done;
    if (count == 0) break;
    used += (size_t)count;
    if (used > size) goto done;
  }
  if (used != size || memchr(secret, 0, size) != NULL ||
      !actql_native_private_file_projection_matches(original->key, original->descriptor)) goto done;
  result = actql_signature_sign_material(library, secret, (int32_t)size,
    original->message, original->message_length, original->expected_public_key,
    original->signature);
  // The native signer has no user callbacks, but another process can replace
  // the private file. Such an attempt remains spent and returns no signature.
  if (!actql_native_private_file_projection_matches(original->key, original->descriptor) ||
      !actql_signature_library_available(library)) result = 6;
done:
  if (secret) {
    volatile unsigned char *clear = secret;
    for (size_t i = 0; i <= size; i++) clear[i] = 0;
    actql_signature_free(library, secret);
  }
  original->primary_status = result;
  if (!actql_original_key_signing_close_descriptor(original)) return 9;
  if (result != 0) memset(original->signature, 0, sizeof(original->signature));
  return result;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_original_key_signing_copy(
  actql_native_original_key_signing *original, moonbit_bytes_t output, int32_t length
) {
  if (!actql_original_key_signing_owner(original) || original->closed ||
      !original->attempted || original->primary_status != 0 ||
      original->descriptor_unconfirmed || original->descriptor >= 0 ||
      !original->child_registered || !actql_signature_library_available(original->library) ||
      !output || length != ACTQL_ED25519_SIGNATURE_BYTES) return 0;
  memcpy(output, original->signature, ACTQL_ED25519_SIGNATURE_BYTES);
  return 1;
}
