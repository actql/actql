#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <dlfcn.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

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
typedef EVP_MD_CTX *(*actql_evp_md_ctx_new_fn)(void);
typedef void (*actql_evp_md_ctx_free_fn)(EVP_MD_CTX *);
typedef int (*actql_evp_digest_verify_init_fn)(
  EVP_MD_CTX *, EVP_PKEY_CTX **, const EVP_MD *, ENGINE *, EVP_PKEY *
);
typedef int (*actql_evp_digest_verify_fn)(
  EVP_MD_CTX *, const unsigned char *, size_t,
  const unsigned char *, size_t
);
typedef unsigned long (*actql_err_get_error_fn)(void);
typedef void (*actql_err_error_string_n_fn)(unsigned long, char *, size_t);

enum {
  ACTQL_NID_ED25519 = 1087,
  ACTQL_ED25519_SIGNATURE_BYTES = 64,
  ACTQL_ED25519_BASE64URL_BYTES = 86
};

typedef struct {
  void *dynamic_library;
  char *error;
  actql_bio_new_mem_buf_fn bio_new_mem_buf;
  actql_bio_free_fn bio_free;
  actql_pem_read_bio_pubkey_fn pem_read_bio_pubkey;
  actql_evp_pkey_free_fn evp_pkey_free;
  actql_evp_pkey_get_base_id_fn evp_pkey_get_base_id;
  actql_evp_md_ctx_new_fn evp_md_ctx_new;
  actql_evp_md_ctx_free_fn evp_md_ctx_free;
  actql_evp_digest_verify_init_fn evp_digest_verify_init;
  actql_evp_digest_verify_fn evp_digest_verify;
  actql_err_get_error_fn err_get_error;
  actql_err_error_string_n_fn err_error_string_n;
} actql_native_signature_library;

static void actql_replace_error(char **target, const char *message) {
  free(*target);
  *target = NULL;
  if (message == NULL) return;
  size_t length = strlen(message);
  char *copy = malloc(length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length + 1);
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

static moonbit_bytes_t actql_copy_message(const char *text) {
  size_t length = text == NULL ? 0 : strlen(text);
  if (length > INT32_MAX) length = INT32_MAX;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, text, length);
  return bytes;
}

static bool actql_load_symbol(
  actql_native_signature_library *library,
  void **target,
  const char *name
) {
  dlerror();
  *target = dlsym(library->dynamic_library, name);
  const char *error = dlerror();
  if (error == NULL && *target != NULL) return true;
  actql_replace_error(&library->error, error == NULL ? name : error);
  return false;
}

#define ACTQL_LOAD(library, field, symbol) \
  actql_load_symbol((library), (void **)&((library)->field), (symbol))

static void actql_native_signature_library_finalize(void *value) {
  actql_native_signature_library *library = value;
  if (library->dynamic_library != NULL) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  free(library->error);
  library->error = NULL;
}

static void actql_openssl_error(
  actql_native_signature_library *library,
  const char *fallback
) {
  unsigned long code = library->err_get_error();
  if (code == 0) {
    actql_replace_error(&library->error, fallback);
    return;
  }
  char buffer[256];
  library->err_error_string_n(code, buffer, sizeof(buffer));
  actql_replace_error(&library->error, buffer);
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
  int32_t length
) {
  actql_native_signature_library *library = moonbit_make_external_object(
    actql_native_signature_library_finalize,
    sizeof(actql_native_signature_library)
  );
  memset(library, 0, sizeof(*library));
  char *name = actql_copy_text(path, length);
  if (name == NULL) {
    actql_replace_error(&library->error, "invalid crypto library path");
    return library;
  }
  library->dynamic_library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
  free(name);
  if (library->dynamic_library == NULL) {
    actql_replace_error(&library->error, dlerror());
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
      !ACTQL_LOAD(library, err_get_error, "ERR_get_error") ||
      !ACTQL_LOAD(library, err_error_string_n, "ERR_error_string_n")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

MOONBIT_FFI_EXPORT
bool actql_native_signature_library_ready(
  actql_native_signature_library *library
) {
  return library != NULL && library->dynamic_library != NULL;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_signature_library_error(
  actql_native_signature_library *library
) {
  return actql_copy_message(library == NULL ? "invalid library" : library->error);
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
  if (library == NULL || library->dynamic_library == NULL ||
      public_key_length <= 0 || public_key_length > 16384 ||
      message_length < 0 || message_length > 1048576) {
    return 2;
  }
  unsigned char decoded[ACTQL_ED25519_SIGNATURE_BYTES];
  if (!actql_decode_ed25519_signature(
        signature, signature_length, decoded)) {
    return 2;
  }
  actql_replace_error(&library->error, NULL);
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
    actql_replace_error(&library->error, "public key is not Ed25519");
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
