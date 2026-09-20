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
  free(client->error);
  free(client->response);
  client->ca_path = NULL;
  client->certificate_path = NULL;
  client->key_path = NULL;
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
  CURL *curl = client->library->easy_init();
  if (curl == NULL) {
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
  ACTQL_SET(ACTQL_CURLOPT_SSLCERT, client->certificate_path);
  ACTQL_SET(ACTQL_CURLOPT_SSLKEY, client->key_path);
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

int32_t actql_native_http_client_get_bearer_file(
  actql_native_http_client *client,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t secret_path,
  int32_t secret_path_length
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
  struct stat expected_secret;
  bool secret_generation_valid =
    lstat(secret_path_text, &expected_secret) == 0 &&
    S_ISREG(expected_secret.st_mode);
  int descriptor = secret_generation_valid
    ? open(secret_path_text, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    : -1;
  free(secret_path_text);
  if (descriptor < 0) {
    free(url_text);
    actql_replace_error(&client->error, "open bearer credential failed");
    return -1;
  }
  enum { ACTQL_MAX_BEARER_BYTES = 8192 };
  unsigned char secret[ACTQL_MAX_BEARER_BYTES + 1];
  size_t secret_length = 0;
  struct stat opened_secret;
  bool secret_valid = fstat(descriptor, &opened_secret) == 0 &&
    S_ISREG(opened_secret.st_mode) &&
    opened_secret.st_dev == expected_secret.st_dev &&
    opened_secret.st_ino == expected_secret.st_ino;
  while (secret_length <= ACTQL_MAX_BEARER_BYTES) {
    ssize_t count = read(
      descriptor,
      secret + secret_length,
      sizeof(secret) - secret_length
    );
    if (count < 0) {
      secret_valid = false;
      break;
    }
    if (count == 0) break;
    secret_length += (size_t)count;
    if (secret_length > ACTQL_MAX_BEARER_BYTES) {
      secret_valid = false;
      break;
    }
  }
  if (close(descriptor) != 0) secret_valid = false;
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
  const char prefix[] = "Authorization: Bearer ";
  size_t authorization_length = sizeof(prefix) - 1 + secret_length;
  char *authorization = secret_valid
    ? malloc(authorization_length + 1)
    : NULL;
  if (authorization == NULL) secret_valid = false;
  if (secret_valid) {
    memcpy(authorization, prefix, sizeof(prefix) - 1);
    memcpy(authorization + sizeof(prefix) - 1, secret, secret_length);
    authorization[authorization_length] = '\0';
  }
  memset(secret, 0, sizeof(secret));
  if (!secret_valid) {
    free(authorization);
    free(url_text);
    actql_replace_error(&client->error, "read bearer credential failed");
    return -1;
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
  ACTQL_SET(ACTQL_CURLOPT_SSLCERT, client->certificate_path);
  ACTQL_SET(ACTQL_CURLOPT_SSLKEY, client->key_path);
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
