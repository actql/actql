#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <dlfcn.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct actql_original_crypto_component actql_original_crypto_component;
static bool actql_crypto_original_thread(actql_original_crypto_component *);
static bool actql_crypto_original_current(actql_original_crypto_component *);
static bool actql_crypto_original_enter(actql_original_crypto_component *);
static void actql_crypto_original_leave(actql_original_crypto_component *);
static int actql_crypto_original_release_library(actql_original_crypto_component *);
static void *actql_crypto_original_symbol(actql_original_crypto_component *, const char *);
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
extern void *actql_bootstrap_current_read_context(void);
extern void *actql_native_file_scoped_allocate(size_t);
extern void actql_native_file_scoped_free(void *);
#endif

typedef struct bio_st BIO;
typedef struct evp_pkey_st EVP_PKEY;
typedef struct evp_md_ctx_st EVP_MD_CTX;
typedef struct evp_pkey_ctx_st EVP_PKEY_CTX;
typedef struct evp_md_st EVP_MD;
typedef struct engine_st ENGINE;

typedef BIO *(*actql_bio_new_mem_buf_fn)(const void *, int);
typedef int (*actql_bio_free_fn)(BIO *);
typedef EVP_PKEY *(*actql_pem_read_bio_pubkey_fn)(
  BIO *, EVP_PKEY **, int (*)(char *, int, int, void *), void *
);
typedef void (*actql_evp_pkey_free_fn)(EVP_PKEY *);
typedef int (*actql_evp_pkey_get_base_id_fn)(const EVP_PKEY *);
typedef int (*actql_evp_pkey_get_raw_public_key_fn)(
  const EVP_PKEY *, unsigned char *, size_t *
);
typedef EVP_MD_CTX *(*actql_evp_md_ctx_new_fn)(void);
typedef void (*actql_evp_md_ctx_free_fn)(EVP_MD_CTX *);
typedef int (*actql_evp_digest_verify_init_fn)(
  EVP_MD_CTX *, EVP_PKEY_CTX **, const EVP_MD *, ENGINE *, EVP_PKEY *
);
typedef int (*actql_evp_digest_verify_fn)(
  EVP_MD_CTX *, const unsigned char *, size_t,
  const unsigned char *, size_t
);
typedef const EVP_MD *(*actql_evp_sha256_fn)(void);
typedef int (*actql_evp_digest_init_ex_fn)(EVP_MD_CTX *, const EVP_MD *, ENGINE *);
typedef int (*actql_evp_digest_update_fn)(EVP_MD_CTX *, const void *, size_t);
typedef int (*actql_evp_digest_final_ex_fn)(EVP_MD_CTX *, unsigned char *, unsigned int *);
typedef unsigned long (*actql_err_get_error_fn)(void);
typedef void (*actql_err_error_string_n_fn)(unsigned long, char *, size_t);

enum {
  ACTQL_NID_ED25519 = 1087,
  ACTQL_ED25519_SIGNATURE_BYTES = 64,
  ACTQL_ED25519_BASE64URL_BYTES = 86
};

typedef struct {
  void *dynamic_library;
  actql_original_crypto_component *component;
  bool component_borrowed;
  bool original_allocator;
  char *error;
  int32_t diagnostic_ceiling;
  uint32_t pending_hashes;
  bool closing;
  bool close_unconfirmed;
  actql_bio_new_mem_buf_fn bio_new_mem_buf;
  actql_bio_free_fn bio_free;
  actql_pem_read_bio_pubkey_fn pem_read_bio_pubkey;
  actql_evp_pkey_free_fn evp_pkey_free;
  actql_evp_pkey_get_base_id_fn evp_pkey_get_base_id;
  actql_evp_md_ctx_new_fn evp_md_ctx_new;
  actql_evp_md_ctx_free_fn evp_md_ctx_free;
  actql_evp_digest_verify_init_fn evp_digest_verify_init;
  actql_evp_digest_verify_fn evp_digest_verify;
  actql_evp_sha256_fn evp_sha256;
  actql_evp_digest_init_ex_fn evp_digest_init_ex;
  actql_evp_digest_update_fn evp_digest_update;
  actql_evp_digest_final_ex_fn evp_digest_final_ex;
  actql_err_get_error_fn err_get_error;
  actql_err_error_string_n_fn err_error_string_n;
  actql_evp_pkey_get_raw_public_key_fn evp_pkey_get_raw_public_key;
} actql_native_signature_library;

// Closing is monotonic. Existing context cleanup may still use cached symbols,
// but no new cryptographic operation can use an alias after close is requested.
static bool actql_signature_library_available(
  const actql_native_signature_library *library
) {
  if (library == NULL) return false;
  if (library->component && !actql_crypto_original_current(library->component)) return false;
  return library->dynamic_library != NULL && !library->closing &&
    (library->component == NULL || library->component_borrowed);
}

/* Legacy allocation domains remain unchanged. Only the original component
 * Library uses its existing provider's scoped native buffer allocation. */
static void *actql_signature_allocate(actql_native_signature_library *library, size_t bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (library->original_allocator) return actql_native_file_scoped_allocate(bytes);
#else
  if (library->original_allocator) return NULL;
#endif
  return malloc(bytes);
}
static void actql_signature_free(actql_native_signature_library *library, void *pointer) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (library->original_allocator) {actql_native_file_scoped_free(pointer);return;}
#else
  if (library->original_allocator) return;
#endif
  free(pointer);
}
typedef struct {actql_original_crypto_component *original; bool entered;} actql_signature_scope;
static actql_signature_scope actql_signature_enter(actql_native_signature_library *library) {
  actql_signature_scope scope = {0};
  if (library == NULL || library->component == NULL) {scope.entered = true;return scope;}
  if (actql_crypto_original_enter(library->component)) {
    scope.original = library->component; scope.entered = true;
  }
  return scope;
}
static void actql_signature_leave(actql_signature_scope *scope) {
  if (scope->entered && scope->original) actql_crypto_original_leave(scope->original);
}
#define ACTQL_SIGNATURE_SCOPE(library, refused) \
  actql_signature_scope original_scope __attribute__((cleanup(actql_signature_leave))) = \
    actql_signature_enter(library); \
  if (!original_scope.entered) return (refused)

// An explicit installer ceiling is independent of row/response limits.
// Zero preserves legacy callers, never evidence of a funded numeric profile.
// Omitted detail is not a valid prefix and cannot erase the original failure.
static bool actql_diagnostic_length(
  const char *message, int32_t ceiling, size_t *length
) {
  if (message == NULL) return false;
  if (ceiling <= 0) { *length = strlen(message); return true; }
  for (size_t i = 0; i <= (size_t)ceiling; i++) {
    if (message[i] == '\0') { *length = i; return true; }
  }
  return false;
}

static void actql_replace_error(
  actql_native_signature_library *library, const char *message
) {
  char **target = &library->error;
  actql_signature_free(library, *target);
  *target = NULL;
  size_t length;
  if (!actql_diagnostic_length(message, library->diagnostic_ceiling, &length)) return;
  char *copy = actql_signature_allocate(library, length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length);
  copy[length] = '\0';
  *target = copy;
}

static char *actql_copy_text(moonbit_bytes_t bytes, int32_t length) {
  if (length <= 0 || memchr(bytes, 0, (size_t)length) != NULL) return NULL;
  char *text = malloc((size_t)length + 1);
  if (text == NULL) return NULL;
  memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static moonbit_bytes_t actql_copy_diagnostic(const char *text, int32_t ceiling) {
  size_t length;
  if (!actql_diagnostic_length(text, ceiling, &length) || length > INT32_MAX)
    length = 0;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, text, length);
  return bytes;
}

static bool actql_load_symbol(
  actql_native_signature_library *library,
  void **target,
  const char *name
) {
  if (library->component != NULL) {
    *target = actql_crypto_original_symbol(library->component, name);
    return *target != NULL;
  }
  dlerror();
  *target = dlsym(library->dynamic_library, name);
  const char *error = dlerror();
  if (error == NULL && *target != NULL) return true;
  actql_replace_error(library, error == NULL ? name : error);
  return false;
}

#define ACTQL_LOAD(library, field, symbol) \
  actql_load_symbol((library), (void **)&((library)->field), (symbol))

static void actql_native_signature_library_finalize(void *value) {
  actql_native_signature_library *library = value;
  if (library->component != NULL) {
    // The original component/Host retains a lost Library borrow; GC cannot
    // release it, unload the component or acknowledge its physical extent.
    if (!actql_crypto_original_thread(library->component)) return;
    if (!library->component_borrowed && !library->pending_hashes) moonbit_decref(library->component);
    return;
  }
  // Finalization is best effort, never an application cleanup acknowledgement.
  // In particular it cannot retry an unconfirmed explicit dlclose.
  if (library->dynamic_library != NULL && !library->close_unconfirmed &&
      library->pending_hashes == 0) {
    if (dlclose(library->dynamic_library) == 0) library->dynamic_library = NULL;
  }
  actql_signature_free(library, library->error);
  library->error = NULL;
}

// The same Library remains the cleanup receiver on pending or unconfirmed
// release. No replacement load, automatic retry or alias-based ACK is issued.
MOONBIT_FFI_EXPORT
int32_t actql_native_signature_library_close(
  actql_native_signature_library *library
) {
  if (library == NULL) return 2;
  if (library->component != NULL) {
    if (!actql_crypto_original_thread(library->component)) return 2;
    if (!library->component_borrowed && library->dynamic_library == NULL) return 0;
    if (!actql_crypto_original_current(library->component)) return 2;
    library->closing = true;
    if (library->pending_hashes != 0) return 1;
    // Original diagnostic buffers cannot outlive the explicit Library ACK.
    actql_signature_free(library, library->error); library->error = NULL;
    if (library->component_borrowed &&
        actql_crypto_original_release_library(library->component) != 0) return 1;
    library->component_borrowed = false;
    library->dynamic_library = NULL;
    return 0;
  }
  library->closing = true;
  if (library->close_unconfirmed) return 3;
  if (library->dynamic_library == NULL) return 0;
  if (library->pending_hashes != 0) return 1;
  dlerror();
  if (dlclose(library->dynamic_library) != 0) {
    const char *issue = dlerror();
    actql_replace_error(library,
      issue == NULL ? "crypto library close unconfirmed" : issue);
    library->close_unconfirmed = true;
    return 3;
  }
  library->dynamic_library = NULL;
  return 0;
}

static void actql_openssl_error(
  actql_native_signature_library *library,
  const char *fallback
) {
  unsigned long code = library->err_get_error();
  if (code == 0) {
    actql_replace_error(library, fallback);
    return;
  }
  char buffer[256];
  library->err_error_string_n(code, buffer, sizeof(buffer));
  actql_replace_error(library, buffer);
}

static int actql_base64url_value(unsigned char character) {
  if (character >= 'A' && character <= 'Z') return character - 'A';
  if (character >= 'a' && character <= 'z') return character - 'a' + 26;
  if (character >= '0' && character <= '9') return character - '0' + 52;
  if (character == '-') return 62;
  if (character == '_') return 63;
  return -1;
}

static bool actql_decode_ed25519_signature(
  moonbit_bytes_t encoded,
  int32_t encoded_length,
  unsigned char output[ACTQL_ED25519_SIGNATURE_BYTES]
) {
  if (encoded_length != ACTQL_ED25519_BASE64URL_BYTES) return false;
  uint32_t accumulator = 0;
  int bits = 0;
  size_t written = 0;
  for (int32_t index = 0; index < encoded_length; index += 1) {
    int value = actql_base64url_value(encoded[index]);
    if (value < 0) return false;
    accumulator = (accumulator << 6) | (uint32_t)value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      if (written >= ACTQL_ED25519_SIGNATURE_BYTES) return false;
      output[written] = (unsigned char)((accumulator >> bits) & 0xffU);
      written += 1;
    }
  }
  if (written != ACTQL_ED25519_SIGNATURE_BYTES) return false;
  return bits == 4 && (accumulator & 0x0fU) == 0;
}

MOONBIT_FFI_EXPORT
void *actql_native_signature_load_library(
  moonbit_bytes_t path,
  int32_t length,
  int32_t diagnostic_ceiling
) {
  actql_native_signature_library *library = moonbit_make_external_object(
    actql_native_signature_library_finalize,
    sizeof(actql_native_signature_library)
  );
  memset(library, 0, sizeof(*library));
  library->diagnostic_ceiling = diagnostic_ceiling;
  char *name = actql_copy_text(path, length);
  if (name == NULL) {
    actql_replace_error(library, "invalid crypto library path");
    return library;
  }
  library->dynamic_library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
  free(name);
  if (library->dynamic_library == NULL) {
    actql_replace_error(library, dlerror());
    return library;
  }
  if (!ACTQL_LOAD(library, bio_new_mem_buf, "BIO_new_mem_buf") ||
      !ACTQL_LOAD(library, bio_free, "BIO_free") ||
      !ACTQL_LOAD(library, pem_read_bio_pubkey, "PEM_read_bio_PUBKEY") ||
      !ACTQL_LOAD(library, evp_pkey_free, "EVP_PKEY_free") ||
      !ACTQL_LOAD(library, evp_pkey_get_base_id, "EVP_PKEY_get_base_id") ||
      !ACTQL_LOAD(library, evp_md_ctx_new, "EVP_MD_CTX_new") ||
      !ACTQL_LOAD(library, evp_md_ctx_free, "EVP_MD_CTX_free") ||
      !ACTQL_LOAD(library, evp_digest_verify_init, "EVP_DigestVerifyInit") ||
      !ACTQL_LOAD(library, evp_digest_verify, "EVP_DigestVerify") ||
      !ACTQL_LOAD(library, evp_sha256, "EVP_sha256") ||
      !ACTQL_LOAD(library, evp_digest_init_ex, "EVP_DigestInit_ex") ||
      !ACTQL_LOAD(library, evp_digest_update, "EVP_DigestUpdate") ||
      !ACTQL_LOAD(library, evp_digest_final_ex, "EVP_DigestFinal_ex") ||
      !ACTQL_LOAD(library, err_get_error, "ERR_get_error") ||
      !ACTQL_LOAD(library, err_error_string_n, "ERR_error_string_n")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

typedef struct {
  actql_native_signature_library *library;
  EVP_MD_CTX *context;
  actql_evp_md_ctx_free_fn free_context;
  bool closed;
} actql_native_sha256;

static void actql_native_sha256_retire_context(
  actql_native_sha256 *hash, bool acknowledge
) {
  if (hash->context != NULL) {
    hash->free_context(hash->context);
    hash->context = NULL;
    if (acknowledge) hash->library->pending_hashes -= 1;
  }
  hash->closed = true;
}

static void actql_native_sha256_finalize(void *value) {
  actql_native_sha256 *hash = value;
  // A lost managed receiver is not an explicit context ACK. Its physical
  // best-effort free cannot let a retained parent Library infer release.
  if (hash->library && hash->library->component &&
      !actql_crypto_original_thread(hash->library->component)) return;
  if (hash->context != NULL && hash->library != NULL) {
    actql_signature_scope scope = actql_signature_enter(hash->library);
    if (!scope.entered) return;
    actql_native_sha256_retire_context(hash, false);
    actql_signature_leave(&scope);
  }
  if (hash->library != NULL) moonbit_decref(hash->library);
  hash->library = NULL;
}

MOONBIT_FFI_EXPORT
bool actql_native_signature_sha256_close(actql_native_sha256 *hash) {
  if (hash == NULL) return false;
  if (hash->library && hash->library->component &&
      !actql_crypto_original_thread(hash->library->component)) return false;
  if (hash->context == NULL) {hash->closed = true;return true;}
  ACTQL_SIGNATURE_SCOPE(hash->library, false);
  actql_native_sha256_retire_context(hash, true);
  return true;
}

MOONBIT_FFI_EXPORT
void *actql_native_signature_sha256_new(
  actql_native_signature_library *library
) {
  actql_native_sha256 *hash = moonbit_make_external_object(
    actql_native_sha256_finalize, sizeof(actql_native_sha256)
  );
  memset(hash, 0, sizeof(*hash));
  if (!actql_signature_library_available(library) ||
      library->pending_hashes == UINT32_MAX) return hash;
  ACTQL_SIGNATURE_SCOPE(library, hash);
  hash->library = library;
  moonbit_incref(library);
  hash->context = library->evp_md_ctx_new();
  hash->free_context = library->evp_md_ctx_free;
  if (hash->context != NULL) library->pending_hashes += 1;
  if (hash->context == NULL ||
      library->evp_digest_init_ex(hash->context, library->evp_sha256(), NULL) != 1) {
    actql_native_sha256_retire_context(hash, true);
  }
  return hash;
}

MOONBIT_FFI_EXPORT
bool actql_native_signature_sha256_ready(actql_native_sha256 *hash) {
  return hash != NULL && actql_signature_library_available(hash->library) &&
    hash->context != NULL && !hash->closed;
}

/* Resolve custody primitives only when used. Signature verification retains
 * its existing library requirements, and no substitute is used on failure. */
MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_random_bytes(
  actql_native_signature_library *library, int32_t length
) {
  ACTQL_SIGNATURE_SCOPE(library, moonbit_make_bytes_raw(0));
  typedef int (*random_fn)(unsigned char *, int);
  random_fn random = NULL;
  if (!actql_signature_library_available(library) ||
      length < 1 || length > 4096 ||
      !actql_load_symbol(library, (void **)&random, "RAND_bytes")) {
    return moonbit_make_bytes_raw(0);
  }
  moonbit_bytes_t result = moonbit_make_bytes_raw(length);
  if (random(result, length) != 1) {
    /* Failed randomness must never escape as key material. */
    memset(result, 0, (size_t)length);
    moonbit_decref(result);
    return moonbit_make_bytes_raw(0);
  }
  return result;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_hmac_sha256(
  actql_native_signature_library *library,
  moonbit_bytes_t key, int32_t key_length,
  moonbit_bytes_t message, int32_t message_length
) {
  ACTQL_SIGNATURE_SCOPE(library, moonbit_make_bytes_raw(0));
  typedef unsigned char *(*hmac_fn)(const EVP_MD *, const void *, int,
    const unsigned char *, size_t, unsigned char *, unsigned int *);
  hmac_fn hmac = NULL;
  if (!actql_signature_library_available(library) ||
      key_length < 1 || key_length > 4096 ||
      message_length < 0 || message_length > 1048576 ||
      !actql_load_symbol(library, (void **)&hmac, "HMAC")) {
    return moonbit_make_bytes_raw(0);
  }
  unsigned char tag[32];
  unsigned int length = 0;
  if (hmac(library->evp_sha256(), key, key_length, message,
      (size_t)message_length, tag, &length) == NULL || length != sizeof(tag)) {
    return moonbit_make_bytes_raw(0);
  }
  moonbit_bytes_t result = moonbit_make_bytes_raw(32);
  memcpy(result, tag, 32);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_signature_equal_tag(
  actql_native_signature_library *library,
  moonbit_bytes_t expected, moonbit_bytes_t supplied
) {
  ACTQL_SIGNATURE_SCOPE(library, 2);
  typedef int (*compare_fn)(const void *, const void *, size_t);
  compare_fn compare = NULL;
  if (!actql_signature_library_available(library) ||
      !actql_load_symbol(library, (void **)&compare, "CRYPTO_memcmp")) return 2;
  return compare(expected, supplied, 32) == 0 ? 0 : 1;
}

MOONBIT_FFI_EXPORT
bool actql_native_signature_sha256_update(
  actql_native_sha256 *hash,
  moonbit_bytes_t bytes,
  int32_t length
) {
  if (hash == NULL || !actql_signature_library_available(hash->library) || hash->context == NULL ||
      hash->closed || length < 0) return false;
  ACTQL_SIGNATURE_SCOPE(hash->library, false);
  return hash->library->evp_digest_update(
    hash->context, bytes, (size_t)length
  ) == 1;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_sha256_finish(
  actql_native_sha256 *hash
) {
  if (hash == NULL || !actql_signature_library_available(hash->library) ||
      hash->context == NULL || hash->closed) {
    return moonbit_make_bytes_raw(0);
  }
  ACTQL_SIGNATURE_SCOPE(hash->library, moonbit_make_bytes_raw(0));
  hash->closed = true;
  unsigned char digest[32];
  unsigned int length = 0;
  int finished = hash->library->evp_digest_final_ex(hash->context, digest, &length);
  actql_native_sha256_retire_context(hash, true);
  if (finished != 1 || length != sizeof(digest)) return moonbit_make_bytes_raw(0);
  moonbit_bytes_t result = moonbit_make_bytes_raw(32);
  memcpy(result, digest, 32);
  return result;
}

MOONBIT_FFI_EXPORT
bool actql_native_signature_library_ready(
  actql_native_signature_library *library
) {
  return actql_signature_library_available(library);
}

// Configuration of the same ready Owner, never inferred from a caller limit.
// No text scan/copy, symbol lookup, crypto operation or state change occurs.
MOONBIT_FFI_EXPORT
int32_t actql_native_signature_library_diagnostic_ceiling(
  actql_native_signature_library *library
) {
  if (!actql_native_signature_library_ready(library) ||
      library->diagnostic_ceiling <= 0) return 0;
  return library->diagnostic_ceiling;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_library_error(
  actql_native_signature_library *library
) {
  if (library == NULL || (library->component != NULL &&
      !actql_crypto_original_current(library->component))) return moonbit_make_bytes_raw(0);
  return actql_copy_diagnostic(library->error, library->diagnostic_ceiling);
}

MOONBIT_FFI_EXPORT
int32_t actql_native_signature_ed25519_public_key_raw32(
  actql_native_signature_library *library,
  moonbit_bytes_t public_key,
  int32_t public_key_length,
  moonbit_bytes_t output,
  int32_t output_length
) {
  ACTQL_SIGNATURE_SCOPE(library, 2);
  if (!actql_signature_library_available(library) ||
      library->diagnostic_ceiling <= 0 || public_key == NULL ||
      public_key_length <= 0 || public_key_length > 16384 ||
      memchr(public_key, 0, (size_t)public_key_length) != NULL ||
      output == NULL || output_length != 32) return 2;
  memset(output, 0, 32);
  actql_replace_error(library, NULL);
  // Optional comparison support does not expand legacy load requirements.
  if (library->evp_pkey_get_raw_public_key == NULL &&
      !ACTQL_LOAD(library, evp_pkey_get_raw_public_key,
                  "EVP_PKEY_get_raw_public_key")) return 5;
  BIO *bio = library->bio_new_mem_buf(public_key, public_key_length);
  if (bio == NULL) {
    actql_openssl_error(library, "public key buffer failed");
    return 3;
  }
  EVP_PKEY *key = library->pem_read_bio_pubkey(bio, NULL, NULL, NULL);
  library->bio_free(bio);
  if (key == NULL) {
    actql_openssl_error(library, "public key decode failed");
    return 3;
  }
  if (library->evp_pkey_get_base_id(key) != ACTQL_NID_ED25519) {
    library->evp_pkey_free(key);
    actql_replace_error(library,
                        "public key is not Ed25519");
    return 4;
  }
  // https://docs.openssl.org/3.0/man3/EVP_PKEY_new/
  // OpenSSL takes capacity on entry and returns the actual length on exit.
  // This projection is comparison material, never a grant CID or permission.
  size_t length = 32;
  int result = library->evp_pkey_get_raw_public_key(key, output, &length);
  library->evp_pkey_free(key);
  if (result != 1 || length != 32) {
    memset(output, 0, 32);
    actql_openssl_error(library, "public key projection failed");
    return 5;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_signature_verify_ed25519(
  actql_native_signature_library *library,
  moonbit_bytes_t public_key,
  int32_t public_key_length,
  moonbit_bytes_t message,
  int32_t message_length,
  moonbit_bytes_t signature,
  int32_t signature_length
) {
  ACTQL_SIGNATURE_SCOPE(library, 2);
  if (!actql_signature_library_available(library) ||
      public_key_length <= 0 || public_key_length > 16384 ||
      message_length < 0 || message_length > 1048576) {
    return 2;
  }
  unsigned char decoded[ACTQL_ED25519_SIGNATURE_BYTES];
  if (!actql_decode_ed25519_signature(
        signature, signature_length, decoded)) {
    return 2;
  }
  actql_replace_error(library, NULL);
  BIO *bio = library->bio_new_mem_buf(public_key, public_key_length);
  if (bio == NULL) {
    actql_openssl_error(library, "public key buffer failed");
    return 3;
  }
  EVP_PKEY *key = library->pem_read_bio_pubkey(bio, NULL, NULL, NULL);
  library->bio_free(bio);
  if (key == NULL) {
    actql_openssl_error(library, "public key decode failed");
    return 3;
  }
  if (library->evp_pkey_get_base_id(key) != ACTQL_NID_ED25519) {
    library->evp_pkey_free(key);
    actql_replace_error(library, "public key is not Ed25519");
    return 4;
  }
  EVP_MD_CTX *context = library->evp_md_ctx_new();
  if (context == NULL) {
    library->evp_pkey_free(key);
    actql_openssl_error(library, "verification context failed");
    return 5;
  }
  int initialized = library->evp_digest_verify_init(
    context, NULL, NULL, NULL, key
  );
  int verified = initialized == 1
    ? library->evp_digest_verify(
        context,
        decoded,
        ACTQL_ED25519_SIGNATURE_BYTES,
        message,
        (size_t)message_length
      )
    : -1;
  library->evp_md_ctx_free(context);
  library->evp_pkey_free(key);
  memset(decoded, 0, sizeof(decoded));
  if (verified == 1) return 0;
  if (verified == 0) return 1;
  actql_openssl_error(library, initialized == 1
    ? "signature verification failed"
    : "signature verification initialization failed");
  return 5;
}

/* No password prompt, external key retrieval or caller-selected file path.
 * Private key bytes have already been selected by the owning assembly. */
static int actql_signing_no_password(char *buffer, int size, int writing, void *data) {
  (void)buffer; (void)size; (void)writing; (void)data;
  return 0;
}

/* Resolve signing symbols only for signing. Existing verification, hashing
 * and Store users retain their original library-loading requirements. */
MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_sign_ed25519(
  actql_native_signature_library *library,
  moonbit_bytes_t private_key,
  int32_t private_key_length,
  moonbit_bytes_t message,
  int32_t message_length
) {
  moonbit_bytes_t result = moonbit_make_bytes_raw(1);
  result[0] = 2;
  ACTQL_SIGNATURE_SCOPE(library, result);
  if (!actql_signature_library_available(library) ||
      private_key_length <= 0 || private_key_length > 16384 ||
      message_length < 0 || message_length > 1048576 ||
      memchr(private_key, 0, (size_t)private_key_length) != NULL) return result;
  actql_pem_read_bio_pubkey_fn read_private = NULL;
  actql_evp_digest_verify_init_fn sign_init = NULL;
  typedef int (*sign_fn)(EVP_MD_CTX *, unsigned char *, size_t *,
                         const unsigned char *, size_t);
  sign_fn sign = NULL;
  result[0] = 5;
  if (!actql_load_symbol(library, (void **)&read_private, "PEM_read_bio_PrivateKey") ||
      !actql_load_symbol(library, (void **)&sign_init, "EVP_DigestSignInit") ||
      !actql_load_symbol(library, (void **)&sign, "EVP_DigestSign")) return result;
  BIO *bio = library->bio_new_mem_buf(private_key, private_key_length);
  if (bio == NULL) return result;
  EVP_PKEY *key = read_private(bio, NULL, actql_signing_no_password, NULL);
  library->bio_free(bio);
  if (key == NULL) { result[0] = 3; return result; }
  if (library->evp_pkey_get_base_id(key) != ACTQL_NID_ED25519) {
    library->evp_pkey_free(key);
    result[0] = 4;
    return result;
  }
  EVP_MD_CTX *context = library->evp_md_ctx_new();
  if (context == NULL) { library->evp_pkey_free(key); return result; }
  unsigned char signature[ACTQL_ED25519_SIGNATURE_BYTES];
  size_t length = sizeof(signature);
  int initialized = sign_init(context, NULL, NULL, NULL, key);
  int signed_message = initialized == 1
    ? sign(context, signature, &length, message, (size_t)message_length) : 0;
  library->evp_md_ctx_free(context);
  library->evp_pkey_free(key);
  if (signed_message == 1 && length == sizeof(signature)) {
    moonbit_decref(result);
    result = moonbit_make_bytes_raw(1 + ACTQL_ED25519_SIGNATURE_BYTES);
    result[0] = 0;
    memcpy(result + 1, signature, sizeof(signature));
  }
  memset(signature, 0, sizeof(signature));
  return result;
}

/* Private evidence uses the same AES-256-GCM algorithm and AAD as the existing
 * Node Store. Optional cipher symbols are resolved only for this operation;
 * signature verification does not acquire a new cipher dependency. */
MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_private_evidence_cipher(
  void *value, moonbit_bytes_t key, int32_t key_length,
  moonbit_bytes_t aad, int32_t aad_length,
  moonbit_bytes_t input, int32_t input_length, int32_t encrypt
) {
  actql_native_signature_library *library = value;
  typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
  typedef struct evp_cipher_st EVP_CIPHER;
  typedef EVP_CIPHER_CTX *(*ctx_new_fn)(void);
  typedef void (*ctx_free_fn)(EVP_CIPHER_CTX *);
  typedef const EVP_CIPHER *(*cipher_fn)(void);
  typedef int (*init_fn)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *,
                        const unsigned char *, const unsigned char *);
  typedef int (*update_fn)(EVP_CIPHER_CTX *, unsigned char *, int *,
                          const unsigned char *, int);
  typedef int (*final_fn)(EVP_CIPHER_CTX *, unsigned char *, int *);
  typedef int (*ctrl_fn)(EVP_CIPHER_CTX *, int, int, void *);
  typedef int (*random_fn)(unsigned char *, int);
  ctx_new_fn ctx_new = NULL; ctx_free_fn ctx_free = NULL;
  cipher_fn aes = NULL; init_fn init = NULL; update_fn update = NULL;
  final_fn final = NULL; ctrl_fn ctrl = NULL; random_fn random = NULL;
  moonbit_bytes_t result = moonbit_make_bytes_raw(1);
  result[0] = 1;
  ACTQL_SIGNATURE_SCOPE(library, result);
  if (!actql_signature_library_available(library) || key_length != 32 ||
      aad_length < 1 || aad_length > 4096 || input_length < 1 ||
      input_length > 1048576 + 28 || (!encrypt && input_length <= 28)) return result;
#define ACTQL_PRIVATE_SYMBOL(target, symbol) \
  actql_load_symbol(library, (void **)&(target), (symbol))
  if (!ACTQL_PRIVATE_SYMBOL(ctx_new, "EVP_CIPHER_CTX_new") ||
      !ACTQL_PRIVATE_SYMBOL(ctx_free, "EVP_CIPHER_CTX_free") ||
      !ACTQL_PRIVATE_SYMBOL(aes, "EVP_aes_256_gcm") ||
      !ACTQL_PRIVATE_SYMBOL(init, encrypt ? "EVP_EncryptInit_ex" : "EVP_DecryptInit_ex") ||
      !ACTQL_PRIVATE_SYMBOL(update, encrypt ? "EVP_EncryptUpdate" : "EVP_DecryptUpdate") ||
      !ACTQL_PRIVATE_SYMBOL(final, encrypt ? "EVP_EncryptFinal_ex" : "EVP_DecryptFinal_ex") ||
      !ACTQL_PRIVATE_SYMBOL(ctrl, "EVP_CIPHER_CTX_ctrl") ||
      !ACTQL_PRIVATE_SYMBOL(random, "RAND_bytes")) return result;
#undef ACTQL_PRIVATE_SYMBOL
  int length = encrypt ? input_length : input_length - 28;
  if (length > 1048576) return result;
  unsigned char *scratch = actql_signature_allocate(library, (size_t)length + 64);
  if (scratch == NULL) return result;
  unsigned char nonce[12];
  unsigned char tag[16];
  unsigned char private_key[32];
  memcpy(private_key, key, 32);
  if (encrypt) {
    if (random(nonce, 12) != 1) goto cleanup;
  } else {
    memcpy(nonce, input, 12);
    memcpy(tag, input + input_length - 16, 16);
  }
  EVP_CIPHER_CTX *context = ctx_new();
  if (context == NULL) goto cleanup;
  int written = 0, tail = 0, ignored = 0;
  int ok = init(context, aes(), NULL, private_key, nonce) == 1 &&
    update(context, NULL, &ignored, aad, aad_length) == 1 &&
    update(context, scratch, &written, encrypt ? input : input + 12, length) == 1;
  if (ok && !encrypt) ok = ctrl(context, 0x11, 16, tag) == 1;
  if (ok) ok = final(context, scratch + written, &tail) == 1;
  if (ok) ok = written + tail == length;
  if (ok && encrypt) ok = ctrl(context, 0x10, 16, tag) == 1;
  ctx_free(context);
  if (ok) {
    moonbit_decref(result);
    result = moonbit_make_bytes_raw(length + (encrypt ? 29 : 1));
    result[0] = 0;
    if (encrypt) {
      memcpy(result + 1, nonce, 12);
      memcpy(result + 13, scratch, (size_t)length);
      memcpy(result + 13 + length, tag, 16);
    } else {
      /* Do not expose any unauthenticated plaintext to the MoonBit heap. */
      memcpy(result + 1, scratch, (size_t)length);
    }
  }
cleanup:
  {
    volatile unsigned char *wipe = private_key;
    for (int i = 0; i < 32; i++) wipe[i] = 0;
    wipe = scratch;
    for (size_t i = 0; i < (size_t)length + 64; i++) wipe[i] = 0;
  }
  actql_signature_free(library, scratch);
  return result;
}

#include "key_generation.h"

#include "original_crypto_component.inc"
