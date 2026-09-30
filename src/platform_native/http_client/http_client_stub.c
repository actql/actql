#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

typedef void CURL;
typedef int CURLcode;
typedef int CURLoption;
typedef int CURLINFO;
typedef int64_t curl_off_t;
typedef struct curl_slist curl_slist;

typedef CURLcode (*actql_curl_global_init_fn)(long);
typedef const char *(*actql_curl_version_fn)(void);
typedef CURL *(*actql_curl_easy_init_fn)(void);
typedef CURLcode (*actql_curl_easy_setopt_fn)(CURL *, CURLoption, ...);
typedef CURLcode (*actql_curl_easy_perform_fn)(CURL *);
typedef CURLcode (*actql_curl_easy_getinfo_fn)(CURL *, CURLINFO, ...);
typedef void (*actql_curl_easy_cleanup_fn)(CURL *);
typedef const char *(*actql_curl_easy_strerror_fn)(CURLcode);
typedef curl_slist *(*actql_curl_slist_append_fn)(curl_slist *, const char *);
typedef void (*actql_curl_slist_free_all_fn)(curl_slist *);

enum {
  ACTQL_CURLE_OK = 0,
  ACTQL_CURLE_WRITE_ERROR = 23,
  ACTQL_CURLE_ABORTED_BY_CALLBACK = 42,
  ACTQL_CURLOPT_WRITEDATA = 10001,
  ACTQL_CURLOPT_URL = 10002,
  ACTQL_CURLOPT_ERRORBUFFER = 10010,
  ACTQL_CURLOPT_WRITEFUNCTION = 20011,
  ACTQL_CURLOPT_POSTFIELDS = 10015,
  ACTQL_CURLOPT_HTTPHEADER = 10023,
  ACTQL_CURLOPT_SSLCERT = 10025,
  ACTQL_CURLOPT_NOPROGRESS = 43,
  ACTQL_CURLOPT_POST = 47,
  ACTQL_CURLOPT_FOLLOWLOCATION = 52,
  ACTQL_CURLOPT_XFERINFODATA = 10057,
  ACTQL_CURLOPT_SSL_VERIFYPEER = 64,
  ACTQL_CURLOPT_CAINFO = 10065,
  ACTQL_CURLOPT_SSL_VERIFYHOST = 81,
  ACTQL_CURLOPT_SSLKEY = 10087,
  ACTQL_CURLOPT_NOSIGNAL = 99,
  ACTQL_CURLOPT_POSTFIELDSIZE_LARGE = 30120,
  ACTQL_CURLOPT_CUSTOMREQUEST = 10036,
  ACTQL_CURLOPT_HTTPGET = 80,
  ACTQL_CURLOPT_TIMEOUT_MS = 155,
  ACTQL_CURLOPT_CONNECTTIMEOUT_MS = 156,
  ACTQL_CURLOPT_XFERINFOFUNCTION = 20219,
  ACTQL_CURLOPT_PROTOCOLS = 181,
  ACTQL_CURLINFO_RESPONSE_CODE = 0x200002,
  ACTQL_CURL_ERROR_SIZE = 256,
  ACTQL_CURL_GLOBAL_ALL = 3
};

typedef struct {
  void *dynamic_library;
  char *error;
  actql_curl_global_init_fn global_init;
  actql_curl_version_fn version;
  actql_curl_easy_init_fn easy_init;
  actql_curl_easy_setopt_fn easy_setopt;
  actql_curl_easy_perform_fn easy_perform;
  actql_curl_easy_getinfo_fn easy_getinfo;
  actql_curl_easy_cleanup_fn easy_cleanup;
  actql_curl_easy_strerror_fn easy_strerror;
  actql_curl_slist_append_fn slist_append;
  actql_curl_slist_free_all_fn slist_free_all;
} actql_native_http_library;

typedef struct {
  actql_native_http_library *library;
  char *ca_path;
  char *certificate_path;
  char *key_path;
  char *bearer_path;
  char *error;
  unsigned char *response;
  size_t response_length;
  size_t response_capacity;
  int64_t max_response_bytes;
  long connect_timeout_ms;
  long operation_timeout_ms;
  long status;
  atomic_bool cancelled;
  bool closed;
  bool capacity_exceeded;
} actql_native_http_client;

static bool actql_same_file_generation(
  const struct stat *left,
  const struct stat *right
) {
  if (left->st_dev != right->st_dev ||
      left->st_ino != right->st_ino ||
      left->st_mode != right->st_mode ||
      left->st_size != right->st_size) {
    return false;
  }
  return left->st_mtime == right->st_mtime &&
    left->st_ctime == right->st_ctime;
}

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

static moonbit_bytes_t actql_copy_bytes(const void *source, size_t length) {
  if (length > INT32_MAX) length = INT32_MAX;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0 && source != NULL) memcpy(bytes, source, length);
  return bytes;
}

static moonbit_bytes_t actql_copy_message(const char *text) {
  return actql_copy_bytes(text, text == NULL ? 0 : strlen(text));
}

static bool actql_load_symbol(
  actql_native_http_library *library,
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

static void actql_native_http_library_finalize(void *value) {
  actql_native_http_library *library = value;
  if (library->dynamic_library != NULL) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  free(library->error);
  library->error = NULL;
}

static void actql_clear_response(actql_native_http_client *client) {
  free(client->response);
  client->response = NULL;
  client->response_length = 0;
  client->response_capacity = 0;
  client->status = 0;
  client->capacity_exceeded = false;
  actql_replace_error(&client->error, NULL);
}

static void actql_native_http_client_finalize(void *value) {
  actql_native_http_client *client = value;
  free(client->ca_path);
  free(client->certificate_path);
  free(client->key_path);
  free(client->bearer_path);
  free(client->error);
  free(client->response);
  client->ca_path = NULL;
  client->certificate_path = NULL;
  client->key_path = NULL;
  client->bearer_path = NULL;
  client->error = NULL;
  client->response = NULL;
  if (client->library != NULL) {
    moonbit_decref(client->library);
    client->library = NULL;
  }
}

static size_t actql_receive_response(
  char *bytes,
  size_t size,
  size_t count,
  void *context
) {
  actql_native_http_client *client = context;
  if (size != 0 && count > SIZE_MAX / size) return 0;
  size_t length = size * count;
  if (length == 0) return 0;
  if (client->response_length > (size_t)client->max_response_bytes ||
      length > (size_t)client->max_response_bytes - client->response_length) {
    client->capacity_exceeded = true;
    return 0;
  }
  size_t required = client->response_length + length;
  if (required > client->response_capacity) {
    size_t capacity = client->response_capacity == 0
      ? ((size_t)client->max_response_bytes < 4096
        ? (size_t)client->max_response_bytes
        : 4096)
      : client->response_capacity;
    while (capacity < required) {
      size_t next = capacity > SIZE_MAX / 2 ? required : capacity * 2;
      if (next > (size_t)client->max_response_bytes) {
        next = (size_t)client->max_response_bytes;
      }
      if (next <= capacity) {
        next = required;
      }
      capacity = next;
    }
    unsigned char *expanded = realloc(client->response, capacity);
    if (expanded == NULL) {
      actql_replace_error(&client->error, "HTTP response allocation failed");
      return 0;
    }
    client->response = expanded;
    client->response_capacity = capacity;
  }
  memcpy(client->response + client->response_length, bytes, length);
  client->response_length = required;
  return length;
}

static int actql_transfer_progress(
  void *context,
  curl_off_t download_total,
  curl_off_t download_now,
  curl_off_t upload_total,
  curl_off_t upload_now
) {
  (void)download_total;
  (void)download_now;
  (void)upload_total;
  (void)upload_now;
  actql_native_http_client *client = context;
  return atomic_load_explicit(&client->cancelled, memory_order_relaxed)
    ? 1
    : 0;
}

static bool actql_option(
  actql_native_http_client *client,
  CURL *curl,
  CURLcode code,
  const char *operation
) {
  if (code == ACTQL_CURLE_OK) return true;
  const char *detail = client->library->easy_strerror(code);
  actql_replace_error(&client->error, detail == NULL ? operation : detail);
  return false;
}

void *actql_native_http_load_library(
  moonbit_bytes_t path,
  int32_t length
) {
  actql_native_http_library *library = moonbit_make_external_object(
    actql_native_http_library_finalize,
    sizeof(actql_native_http_library)
  );
  memset(library, 0, sizeof(*library));
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&library->error, "HTTP library path is invalid");
    return library;
  }
  library->dynamic_library = dlopen(path_text, RTLD_NOW | RTLD_LOCAL);
  free(path_text);
  if (library->dynamic_library == NULL) {
    actql_replace_error(&library->error, dlerror());
    return library;
  }
  if (!ACTQL_LOAD(library, global_init, "curl_global_init") ||
      !ACTQL_LOAD(library, version, "curl_version") ||
      !ACTQL_LOAD(library, easy_init, "curl_easy_init") ||
      !ACTQL_LOAD(library, easy_setopt, "curl_easy_setopt") ||
      !ACTQL_LOAD(library, easy_perform, "curl_easy_perform") ||
      !ACTQL_LOAD(library, easy_getinfo, "curl_easy_getinfo") ||
      !ACTQL_LOAD(library, easy_cleanup, "curl_easy_cleanup") ||
      !ACTQL_LOAD(library, easy_strerror, "curl_easy_strerror") ||
      !ACTQL_LOAD(library, slist_append, "curl_slist_append") ||
      !ACTQL_LOAD(library, slist_free_all, "curl_slist_free_all")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
    return library;
  }
  CURLcode code = library->global_init(ACTQL_CURL_GLOBAL_ALL);
  if (code != ACTQL_CURLE_OK) {
    actql_replace_error(&library->error, library->easy_strerror(code));
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

int32_t actql_native_http_library_ready(
  actql_native_http_library *library
) {
  return library != NULL && library->dynamic_library != NULL;
}

moonbit_bytes_t actql_native_http_library_error(
  actql_native_http_library *library
) {
  return actql_copy_message(
    library == NULL ? "invalid HTTP library" : library->error
  );
}

moonbit_bytes_t actql_native_http_library_version(
  actql_native_http_library *library
) {
  if (library == NULL || library->dynamic_library == NULL) {
    return actql_copy_message("");
  }
  return actql_copy_message(library->version());
}

enum { ACTQL_BEARER_FILE_MAX_BYTES = 4096 };

static bool actql_bearer_token_byte(unsigned char value) {
  return (value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z') ||
    (value >= '0' && value <= '9') || value == '-' || value == '.' ||
    value == '_' || value == '~' || value == '+' || value == '/';
}

// RFC 6750 b64token: token characters followed only by trailing '='.
static bool actql_bearer_b64token(const unsigned char *token, size_t length) {
  size_t index = 0;
  while (index < length && actql_bearer_token_byte(token[index])) index += 1;
  if (index == 0) return false;
  while (index < length && token[index] == '=') index += 1;
  return index == length;
}

// Reads "Authorization: Bearer <token>" from an exact local file for one
// request. The checks apply to the opened descriptor: a regular file owned by
// this process's user, not readable or writable by group or others, the same
// file generation throughout, read within a fixed bound. A strict read also
// admits only an RFC 6750 b64token with at most one trailing newline. The
// secret is zeroed on every path and never enters an error message.
static bool actql_read_bearer_authorization(
  const char *path,
  size_t max_bytes,
  bool strict,
  char **authorization_out,
  size_t *authorization_length_out
) {
  *authorization_out = NULL;
  *authorization_length_out = 0;
  enum { ACTQL_BEARER_BUFFER_BYTES = 8192 };
  if (path == NULL || max_bytes == 0 || max_bytes > ACTQL_BEARER_BUFFER_BYTES) {
    return false;
  }
  struct stat expected_secret;
  bool secret_generation_valid =
    lstat(path, &expected_secret) == 0 && S_ISREG(expected_secret.st_mode);
  int descriptor = secret_generation_valid
    ? open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    : -1;
  if (descriptor < 0) return false;
  unsigned char secret[ACTQL_BEARER_BUFFER_BYTES + 1];
  size_t secret_length = 0;
  struct stat opened_secret;
  bool secret_valid = fstat(descriptor, &opened_secret) == 0 &&
    S_ISREG(opened_secret.st_mode) &&
    actql_same_file_generation(&expected_secret, &opened_secret) &&
    (opened_secret.st_mode & 077) == 0 &&
    (!strict || opened_secret.st_uid == geteuid());
  while (secret_valid && secret_length <= max_bytes) {
    ssize_t count = read(
      descriptor,
      secret + secret_length,
      max_bytes + 1 - secret_length
    );
    if (count < 0) {
      secret_valid = false;
      break;
    }
    if (count == 0) break;
    secret_length += (size_t)count;
    if (secret_length > max_bytes) {
      secret_valid = false;
      break;
    }
  }
  unsigned char verified_secret[ACTQL_BEARER_BUFFER_BYTES + 1];
  size_t verified_length = 0;
  if (secret_valid && lseek(descriptor, 0, SEEK_SET) < 0) {
    secret_valid = false;
  }
  while (secret_valid && verified_length <= max_bytes) {
    ssize_t count = read(
      descriptor,
      verified_secret + verified_length,
      max_bytes + 1 - verified_length
    );
    if (count < 0) {
      secret_valid = false;
      break;
    }
    if (count == 0) break;
    verified_length += (size_t)count;
    if (verified_length > max_bytes) {
      secret_valid = false;
      break;
    }
  }
  if (secret_valid &&
      (verified_length != secret_length ||
       memcmp(secret, verified_secret, secret_length) != 0)) {
    secret_valid = false;
  }
  memset(verified_secret, 0, sizeof(verified_secret));
  struct stat completed_secret;
  if (fstat(descriptor, &completed_secret) != 0 ||
      !actql_same_file_generation(&opened_secret, &completed_secret)) {
    secret_valid = false;
  }
  if (close(descriptor) != 0) secret_valid = false;
  if (strict) {
    if (secret_length > 0 && secret[secret_length - 1] == '\n') {
      secret_length -= 1;
    }
    if (!actql_bearer_b64token(secret, secret_length)) secret_valid = false;
  } else {
    while (secret_length > 0 &&
           (secret[secret_length - 1] == '\n' ||
            secret[secret_length - 1] == '\r')) {
      secret_length -= 1;
    }
    if (secret_length == 0 ||
        memchr(secret, 0, secret_length) != NULL ||
        memchr(secret, '\n', secret_length) != NULL ||
        memchr(secret, '\r', secret_length) != NULL) {
      secret_valid = false;
    }
  }
  const char prefix[] = "Authorization: Bearer ";
  size_t authorization_length = sizeof(prefix) - 1 + secret_length;
  char *authorization = secret_valid
    ? malloc(authorization_length + 1)
    : NULL;
  if (authorization != NULL) {
    memcpy(authorization, prefix, sizeof(prefix) - 1);
    memcpy(authorization + sizeof(prefix) - 1, secret, secret_length);
    authorization[authorization_length] = '\0';
  }
  memset(secret, 0, sizeof(secret));
  if (authorization == NULL) return false;
  *authorization_out = authorization;
  *authorization_length_out = authorization_length;
  return true;
}

static void actql_forget_authorization(char *authorization, size_t length) {
  if (authorization == NULL) return;
  memset(authorization, 0, length);
  free(authorization);
}

void *actql_native_http_create_client(
  actql_native_http_library *library,
  moonbit_bytes_t ca_path,
  int32_t ca_path_length,
  moonbit_bytes_t certificate_path,
  int32_t certificate_path_length,
  moonbit_bytes_t key_path,
  int32_t key_path_length,
  int64_t max_response_bytes,
  int32_t connect_timeout_ms,
  int32_t operation_timeout_ms
) {
  actql_native_http_client *client = moonbit_make_external_object(
    actql_native_http_client_finalize,
    sizeof(actql_native_http_client)
  );
  memset(client, 0, sizeof(*client));
  atomic_init(&client->cancelled, false);
  client->library = library;
  if (library != NULL) moonbit_incref(library);
  client->max_response_bytes = max_response_bytes;
  client->connect_timeout_ms = connect_timeout_ms;
  client->operation_timeout_ms = operation_timeout_ms;
  if (library == NULL || library->dynamic_library == NULL ||
      max_response_bytes < 0 || max_response_bytes > INT32_MAX ||
      connect_timeout_ms <= 0 || operation_timeout_ms < connect_timeout_ms) {
    actql_replace_error(&client->error, "invalid HTTP client configuration");
    return client;
  }
  client->ca_path = actql_copy_text(ca_path, ca_path_length);
  client->certificate_path = actql_copy_text(
    certificate_path,
    certificate_path_length
  );
  client->key_path = actql_copy_text(key_path, key_path_length);
  if (client->ca_path == NULL || client->certificate_path == NULL ||
      client->key_path == NULL) {
    actql_replace_error(&client->error, "HTTP credential path allocation failed");
  }
  return client;
}

// A client authenticated by a client certificate, by a per-request bearer
// credential file, or by both. The server is always verified against the CA.
void *actql_native_http_create_authenticated_client(
  actql_native_http_library *library,
  moonbit_bytes_t ca_path,
  int32_t ca_path_length,
  moonbit_bytes_t certificate_path,
  int32_t certificate_path_length,
  moonbit_bytes_t key_path,
  int32_t key_path_length,
  moonbit_bytes_t bearer_path,
  int32_t bearer_path_length,
  int64_t max_response_bytes,
  int32_t connect_timeout_ms,
  int32_t operation_timeout_ms
) {
  actql_native_http_client *client = moonbit_make_external_object(
    actql_native_http_client_finalize,
    sizeof(actql_native_http_client)
  );
  memset(client, 0, sizeof(*client));
  atomic_init(&client->cancelled, false);
  client->library = library;
  if (library != NULL) moonbit_incref(library);
  client->max_response_bytes = max_response_bytes;
  client->connect_timeout_ms = connect_timeout_ms;
  client->operation_timeout_ms = operation_timeout_ms;
  bool mutual = certificate_path_length > 0 || key_path_length > 0;
  bool bearer = bearer_path_length > 0;
  if (library == NULL || library->dynamic_library == NULL ||
      max_response_bytes < 0 || max_response_bytes > INT32_MAX ||
      connect_timeout_ms <= 0 || operation_timeout_ms < connect_timeout_ms ||
      (!mutual && !bearer) ||
      (mutual && (certificate_path_length <= 0 || key_path_length <= 0))) {
    actql_replace_error(&client->error, "invalid HTTP client configuration");
    return client;
  }
  client->ca_path = actql_copy_text(ca_path, ca_path_length);
  if (mutual) {
    client->certificate_path = actql_copy_text(
      certificate_path,
      certificate_path_length
    );
    client->key_path = actql_copy_text(key_path, key_path_length);
  }
  if (bearer) {
    client->bearer_path = actql_copy_text(bearer_path, bearer_path_length);
  }
  if (client->ca_path == NULL ||
      (mutual && (client->certificate_path == NULL ||
        client->key_path == NULL)) ||
      (bearer && client->bearer_path == NULL)) {
    actql_replace_error(&client->error, "HTTP credential path allocation failed");
  }
  return client;
}

int32_t actql_native_http_client_ready(actql_native_http_client *client) {
  return client != NULL && client->library != NULL &&
    client->library->dynamic_library != NULL && client->error == NULL &&
    !client->closed;
}

moonbit_bytes_t actql_native_http_client_error(
  actql_native_http_client *client
) {
  return actql_copy_message(
    client == NULL ? "invalid HTTP client" : client->error
  );
}

int32_t actql_native_http_client_post_json(
  actql_native_http_client *client,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t body,
  int32_t body_length
) {
  if (client == NULL || client->closed) return 3;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return 2;
  actql_clear_response(client);
  char *url_text = actql_copy_text(url, url_length);
  if (url_text == NULL) {
    actql_replace_error(&client->error, "invalid HTTPS URL");
    return -1;
  }
  char *authorization = NULL;
  size_t authorization_length = 0;
  if (client->bearer_path != NULL &&
      !actql_read_bearer_authorization(
        client->bearer_path,
        ACTQL_BEARER_FILE_MAX_BYTES,
        true,
        &authorization,
        &authorization_length
      )) {
    free(url_text);
    actql_replace_error(&client->error, "bearer credential unavailable");
    return 5;
  }
  CURL *curl = client->library->easy_init();
  if (curl == NULL) {
    actql_forget_authorization(authorization, authorization_length);
    free(url_text);
    actql_replace_error(&client->error, "initialize HTTP request failed");
    return -1;
  }
  char error_buffer[ACTQL_CURL_ERROR_SIZE];
  memset(error_buffer, 0, sizeof(error_buffer));
  curl_slist *headers = client->library->slist_append(
    NULL,
    "Content-Type: application/json"
  );
  bool configured = headers != NULL;
  if (configured) {
    curl_slist *next_headers = client->library->slist_append(
      headers,
      "Accept: application/json"
    );
    if (next_headers == NULL) {
      configured = false;
      actql_replace_error(&client->error, "HTTP header allocation failed");
    } else {
      headers = next_headers;
    }
  }
  if (configured && authorization != NULL) {
    curl_slist *next_headers = client->library->slist_append(
      headers,
      authorization
    );
    if (next_headers == NULL) {
      configured = false;
      actql_replace_error(&client->error, "HTTP header allocation failed");
    } else {
      headers = next_headers;
    }
  }
  actql_forget_authorization(authorization, authorization_length);
#define ACTQL_SET(option, value) \
  do { \
    if (configured && !actql_option( \
          client, curl, client->library->easy_setopt(curl, (option), (value)), \
          "configure HTTP request failed" \
        )) configured = false; \
  } while (0)
  ACTQL_SET(ACTQL_CURLOPT_URL, url_text);
  ACTQL_SET(ACTQL_CURLOPT_ERRORBUFFER, error_buffer);
  ACTQL_SET(ACTQL_CURLOPT_POST, 1L);
  ACTQL_SET(ACTQL_CURLOPT_POSTFIELDS, body);
  ACTQL_SET(ACTQL_CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)body_length);
  ACTQL_SET(ACTQL_CURLOPT_HTTPHEADER, headers);
  ACTQL_SET(ACTQL_CURLOPT_CAINFO, client->ca_path);
  if (client->certificate_path != NULL) {
    ACTQL_SET(ACTQL_CURLOPT_SSLCERT, client->certificate_path);
    ACTQL_SET(ACTQL_CURLOPT_SSLKEY, client->key_path);
  }
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYPEER, 1L);
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYHOST, 2L);
  ACTQL_SET(ACTQL_CURLOPT_FOLLOWLOCATION, 0L);
  ACTQL_SET(ACTQL_CURLOPT_PROTOCOLS, 2L);
  ACTQL_SET(ACTQL_CURLOPT_NOSIGNAL, 1L);
  ACTQL_SET(ACTQL_CURLOPT_CONNECTTIMEOUT_MS, client->connect_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_TIMEOUT_MS, client->operation_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_WRITEFUNCTION, actql_receive_response);
  ACTQL_SET(ACTQL_CURLOPT_WRITEDATA, client);
  ACTQL_SET(ACTQL_CURLOPT_NOPROGRESS, 0L);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFOFUNCTION, actql_transfer_progress);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFODATA, client);
#undef ACTQL_SET
  CURLcode code = configured
    ? client->library->easy_perform(curl)
    : ACTQL_CURLE_WRITE_ERROR;
  if (configured && code == ACTQL_CURLE_OK) {
    code = client->library->easy_getinfo(
      curl,
      ACTQL_CURLINFO_RESPONSE_CODE,
      &client->status
    );
  }
  if (code != ACTQL_CURLE_OK && client->error == NULL &&
      !client->capacity_exceeded &&
      !atomic_load_explicit(&client->cancelled, memory_order_relaxed)) {
    const char *message = error_buffer[0] == '\0'
      ? client->library->easy_strerror(code)
      : error_buffer;
    actql_replace_error(&client->error, message);
  }
  client->library->slist_free_all(headers);
  client->library->easy_cleanup(curl);
  free(url_text);
  if (client->capacity_exceeded) return 1;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed) ||
      code == ACTQL_CURLE_ABORTED_BY_CALLBACK) return 2;
  return code == ACTQL_CURLE_OK ? 0 : -1;
}

static bool actql_http_header_name_byte(unsigned char value) {
  return (value >= 'a' && value <= 'z') ||
    (value >= '0' && value <= '9') || value == '-';
}

static curl_slist *actql_http_headers_from_block(
  actql_native_http_client *client,
  moonbit_bytes_t block,
  int32_t length,
  bool *valid
) {
  *valid = false;
  if (length < 0 || length > 32768) {
    actql_replace_error(&client->error, "invalid HTTP header block");
    return NULL;
  }
  curl_slist *headers = NULL;
  int32_t offset = 0;
  while (offset < length) {
    int32_t end = offset;
    while (end < length && block[end] != '\n') end += 1;
    if (end == length || end == offset) goto invalid;
    int32_t colon = offset;
    while (colon < end && block[colon] != ':') colon += 1;
    if (colon == offset || colon == end || colon + 1 >= end ||
        block[colon + 1] != ' ') goto invalid;
    for (int32_t index = offset; index < colon; index += 1) {
      if (!actql_http_header_name_byte(block[index])) goto invalid;
    }
    // A configured bearer credential is the only Authorization header.
    if (client->bearer_path != NULL && colon - offset == 13 &&
        memcmp(block + offset, "authorization", 13) == 0) goto invalid;
    for (int32_t index = colon + 2; index < end; index += 1) {
      if (block[index] < 32 || block[index] > 126) goto invalid;
    }
    size_t line_length = (size_t)(end - offset);
    char *line = malloc(line_length + 1);
    if (line == NULL) {
      actql_replace_error(&client->error, "HTTP header allocation failed");
      client->library->slist_free_all(headers);
      return NULL;
    }
    memcpy(line, block + offset, line_length);
    line[line_length] = '\0';
    curl_slist *next = client->library->slist_append(headers, line);
    free(line);
    if (next == NULL) {
      actql_replace_error(&client->error, "HTTP header allocation failed");
      client->library->slist_free_all(headers);
      return NULL;
    }
    headers = next;
    offset = end + 1;
  }
  *valid = true;
  return headers;

invalid:
  actql_replace_error(&client->error, "invalid HTTP header block");
  client->library->slist_free_all(headers);
  return NULL;
}

int32_t actql_native_http_client_request(
  actql_native_http_client *client,
  moonbit_bytes_t method,
  int32_t method_length,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t headers_block,
  int32_t headers_length,
  moonbit_bytes_t body,
  int32_t body_length
) {
  if (client == NULL || client->closed) return 3;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return 2;
  actql_clear_response(client);
  char *method_text = actql_copy_text(method, method_length);
  char *url_text = actql_copy_text(url, url_length);
  bool is_get = method_text != NULL && strcmp(method_text, "GET") == 0;
  bool is_post = method_text != NULL && strcmp(method_text, "POST") == 0;
  bool is_put = method_text != NULL && strcmp(method_text, "PUT") == 0;
  if (url_text == NULL || (!is_get && !is_post && !is_put) ||
      body_length < 0 || (is_get && body_length != 0)) {
    free(method_text);
    free(url_text);
    actql_replace_error(&client->error, "invalid HTTPS request");
    return -1;
  }
  bool headers_valid = false;
  curl_slist *headers = actql_http_headers_from_block(
    client,
    headers_block,
    headers_length,
    &headers_valid
  );
  if (!headers_valid) {
    free(method_text);
    free(url_text);
    return 6;
  }
  if (client->bearer_path != NULL) {
    char *authorization = NULL;
    size_t authorization_length = 0;
    if (!actql_read_bearer_authorization(
          client->bearer_path,
          ACTQL_BEARER_FILE_MAX_BYTES,
          true,
          &authorization,
          &authorization_length
        )) {
      client->library->slist_free_all(headers);
      free(method_text);
      free(url_text);
      actql_replace_error(&client->error, "bearer credential unavailable");
      return 5;
    }
    curl_slist *next_headers = client->library->slist_append(
      headers,
      authorization
    );
    actql_forget_authorization(authorization, authorization_length);
    if (next_headers == NULL) {
      client->library->slist_free_all(headers);
      free(method_text);
      free(url_text);
      actql_replace_error(&client->error, "HTTP header allocation failed");
      return -1;
    }
    headers = next_headers;
  }
  CURL *curl = client->library->easy_init();
  if (curl == NULL) {
    client->library->slist_free_all(headers);
    free(method_text);
    free(url_text);
    actql_replace_error(&client->error, "initialize HTTP request failed");
    return -1;
  }
  char error_buffer[ACTQL_CURL_ERROR_SIZE];
  memset(error_buffer, 0, sizeof(error_buffer));
  bool configured = true;
#define ACTQL_SET(option, value) \
  do { \
    if (configured && !actql_option( \
          client, curl, client->library->easy_setopt(curl, (option), (value)), \
          "configure HTTP request failed" \
        )) configured = false; \
  } while (0)
  ACTQL_SET(ACTQL_CURLOPT_URL, url_text);
  ACTQL_SET(ACTQL_CURLOPT_ERRORBUFFER, error_buffer);
  if (is_get) {
    ACTQL_SET(ACTQL_CURLOPT_HTTPGET, 1L);
  } else {
    if (is_post) ACTQL_SET(ACTQL_CURLOPT_POST, 1L);
    if (is_put) ACTQL_SET(ACTQL_CURLOPT_CUSTOMREQUEST, method_text);
    ACTQL_SET(ACTQL_CURLOPT_POSTFIELDS, body);
    ACTQL_SET(ACTQL_CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)body_length);
  }
  ACTQL_SET(ACTQL_CURLOPT_HTTPHEADER, headers);
  ACTQL_SET(ACTQL_CURLOPT_CAINFO, client->ca_path);
  if (client->certificate_path != NULL) {
    ACTQL_SET(ACTQL_CURLOPT_SSLCERT, client->certificate_path);
    ACTQL_SET(ACTQL_CURLOPT_SSLKEY, client->key_path);
  }
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYPEER, 1L);
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYHOST, 2L);
  ACTQL_SET(ACTQL_CURLOPT_FOLLOWLOCATION, 0L);
  ACTQL_SET(ACTQL_CURLOPT_PROTOCOLS, 2L);
  ACTQL_SET(ACTQL_CURLOPT_NOSIGNAL, 1L);
  ACTQL_SET(ACTQL_CURLOPT_CONNECTTIMEOUT_MS, client->connect_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_TIMEOUT_MS, client->operation_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_WRITEFUNCTION, actql_receive_response);
  ACTQL_SET(ACTQL_CURLOPT_WRITEDATA, client);
  ACTQL_SET(ACTQL_CURLOPT_NOPROGRESS, 0L);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFOFUNCTION, actql_transfer_progress);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFODATA, client);
#undef ACTQL_SET
  CURLcode code = configured
    ? client->library->easy_perform(curl)
    : ACTQL_CURLE_WRITE_ERROR;
  if (configured && code == ACTQL_CURLE_OK) {
    code = client->library->easy_getinfo(
      curl,
      ACTQL_CURLINFO_RESPONSE_CODE,
      &client->status
    );
  }
  if (code != ACTQL_CURLE_OK && client->error == NULL &&
      !client->capacity_exceeded &&
      !atomic_load_explicit(&client->cancelled, memory_order_relaxed)) {
    const char *message = error_buffer[0] == '\0'
      ? client->library->easy_strerror(code)
      : error_buffer;
    actql_replace_error(&client->error, message);
  }
  client->library->slist_free_all(headers);
  client->library->easy_cleanup(curl);
  free(method_text);
  free(url_text);
  if (client->capacity_exceeded) return 1;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed) ||
      code == ACTQL_CURLE_ABORTED_BY_CALLBACK) return 2;
  return code == ACTQL_CURLE_OK ? 0 : -1;
}

int32_t actql_native_http_client_get_bearer_file(
  actql_native_http_client *client,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t secret_path,
  int32_t secret_path_length,
  int64_t expires_at_milliseconds
) {
  if (client == NULL || client->closed) return 3;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return 2;
  actql_clear_response(client);
  char *url_text = actql_copy_text(url, url_length);
  char *secret_path_text = actql_copy_text(secret_path, secret_path_length);
  if (url_text == NULL || secret_path_text == NULL) {
    free(url_text);
    free(secret_path_text);
    actql_replace_error(&client->error, "invalid HTTPS credential request");
    return -1;
  }
  char *authorization = NULL;
  size_t authorization_length = 0;
  bool secret_valid = actql_read_bearer_authorization(
    secret_path_text,
    8192,
    false,
    &authorization,
    &authorization_length
  );
  free(secret_path_text);
  if (!secret_valid) {
    free(url_text);
    actql_replace_error(&client->error, "read bearer credential failed");
    return -1;
  }
  struct timespec observed_time;
  bool deadline_valid = expires_at_milliseconds > 0 &&
    clock_gettime(CLOCK_REALTIME, &observed_time) == 0 &&
    observed_time.tv_sec >= 0 &&
    observed_time.tv_sec <= INT64_MAX / 1000 &&
    observed_time.tv_sec * 1000 + observed_time.tv_nsec / 1000000 <
      expires_at_milliseconds;
  if (!deadline_valid) {
    memset(authorization, 0, authorization_length);
    free(authorization);
    free(url_text);
    actql_replace_error(&client->error, "credential deadline expired");
    return 4;
  }
  CURL *curl = client->library->easy_init();
  if (curl == NULL) {
    memset(authorization, 0, authorization_length);
    free(authorization);
    free(url_text);
    actql_replace_error(&client->error, "initialize HTTP request failed");
    return -1;
  }
  char error_buffer[ACTQL_CURL_ERROR_SIZE];
  memset(error_buffer, 0, sizeof(error_buffer));
  curl_slist *headers = client->library->slist_append(
    NULL,
    "Accept: application/json"
  );
  bool configured = headers != NULL;
  if (configured) {
    curl_slist *next_headers = client->library->slist_append(
      headers,
      authorization
    );
    if (next_headers == NULL) {
      configured = false;
      actql_replace_error(&client->error, "HTTP header allocation failed");
    } else {
      headers = next_headers;
    }
  }
  memset(authorization, 0, authorization_length);
  free(authorization);
#define ACTQL_SET(option, value) \
  do { \
    if (configured && !actql_option( \
          client, curl, client->library->easy_setopt(curl, (option), (value)), \
          "configure HTTP request failed" \
        )) configured = false; \
  } while (0)
  ACTQL_SET(ACTQL_CURLOPT_URL, url_text);
  ACTQL_SET(ACTQL_CURLOPT_ERRORBUFFER, error_buffer);
  ACTQL_SET(ACTQL_CURLOPT_HTTPHEADER, headers);
  ACTQL_SET(ACTQL_CURLOPT_CAINFO, client->ca_path);
  if (client->certificate_path != NULL) {
    ACTQL_SET(ACTQL_CURLOPT_SSLCERT, client->certificate_path);
    ACTQL_SET(ACTQL_CURLOPT_SSLKEY, client->key_path);
  }
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYPEER, 1L);
  ACTQL_SET(ACTQL_CURLOPT_SSL_VERIFYHOST, 2L);
  ACTQL_SET(ACTQL_CURLOPT_FOLLOWLOCATION, 0L);
  ACTQL_SET(ACTQL_CURLOPT_PROTOCOLS, 2L);
  ACTQL_SET(ACTQL_CURLOPT_NOSIGNAL, 1L);
  ACTQL_SET(ACTQL_CURLOPT_CONNECTTIMEOUT_MS, client->connect_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_TIMEOUT_MS, client->operation_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_WRITEFUNCTION, actql_receive_response);
  ACTQL_SET(ACTQL_CURLOPT_WRITEDATA, client);
  ACTQL_SET(ACTQL_CURLOPT_NOPROGRESS, 0L);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFOFUNCTION, actql_transfer_progress);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFODATA, client);
#undef ACTQL_SET
  CURLcode code = configured
    ? client->library->easy_perform(curl)
    : ACTQL_CURLE_WRITE_ERROR;
  if (configured && code == ACTQL_CURLE_OK) {
    code = client->library->easy_getinfo(
      curl,
      ACTQL_CURLINFO_RESPONSE_CODE,
      &client->status
    );
  }
  if (code != ACTQL_CURLE_OK && client->error == NULL &&
      !client->capacity_exceeded &&
      !atomic_load_explicit(&client->cancelled, memory_order_relaxed)) {
    const char *message = error_buffer[0] == '\0'
      ? client->library->easy_strerror(code)
      : error_buffer;
    actql_replace_error(&client->error, message);
  }
  client->library->slist_free_all(headers);
  client->library->easy_cleanup(curl);
  free(url_text);
  if (client->capacity_exceeded) return 1;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed) ||
      code == ACTQL_CURLE_ABORTED_BY_CALLBACK) return 2;
  return code == ACTQL_CURLE_OK ? 0 : -1;
}

int32_t actql_native_http_client_status(actql_native_http_client *client) {
  if (client == NULL || client->status < 0 || client->status > INT32_MAX) {
    return 0;
  }
  return (int32_t)client->status;
}

moonbit_bytes_t actql_native_http_client_body(
  actql_native_http_client *client
) {
  if (client == NULL) return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(client->response, client->response_length);
}

int32_t actql_native_http_client_cancel(actql_native_http_client *client) {
  if (client == NULL || client->closed) return false;
  return !atomic_exchange_explicit(
    &client->cancelled,
    true,
    memory_order_relaxed
  );
}

int32_t actql_native_http_client_close(actql_native_http_client *client) {
  if (client == NULL || client->closed) return false;
  client->closed = true;
  atomic_store_explicit(&client->cancelled, true, memory_order_relaxed);
  actql_clear_response(client);
  return true;
}
