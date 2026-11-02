#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#define _GNU_SOURCE

#include "moonbit.h"
#include "../filesystem/private_file_projection.h"
#include "component_tls_lifetime.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <pthread.h>
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
typedef struct actql_read_context actql_read_context;
typedef struct actql_owned_capacity actql_owned_capacity;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
#include "owned_capacity.h"
extern void *actql_bootstrap_current_read_context(void);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);
extern void *actql_native_private_scoped_allocate(size_t);
extern int actql_native_private_scoped_free(void *);
extern int actql_native_private_scoped_contains_allocation(actql_read_context *, actql_owned_capacity *, const void *, size_t);
extern actql_owned_capacity *actql_native_owned_current(void);
extern int actql_native_owned_enter(actql_owned_capacity *);
extern int actql_native_owned_leave(actql_owned_capacity *);
extern int actql_read_context_enter(actql_read_context *);
extern int actql_read_context_leave(actql_read_context *);
#endif

typedef CURLcode (*actql_curl_global_init_fn)(long);
typedef CURLcode (*actql_curl_global_init_mem_fn)(long, void *(*)(size_t),
  void (*)(void *), void *(*)(void *, size_t), char *(*)(const char *), void *(*)(size_t, size_t));
typedef void (*actql_curl_global_cleanup_fn)(void);
typedef struct { int age; const char *version; unsigned int version_num; const char *host; int features; } actql_curl_version_info;
typedef const actql_curl_version_info *(*actql_curl_version_info_fn)(int);
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
  ACTQL_CURLOPT_QUICK_EXIT = 322,
  ACTQL_CURLINFO_RESPONSE_CODE = 0x200002,
  ACTQL_CURL_ERROR_SIZE = 256,
  ACTQL_CURL_GLOBAL_ALL = 3,
  ACTQL_CURL_VERSION_THREADSAFE = 1U << 30
};

typedef struct {
  void *dynamic_library;
  char *error;
  int32_t diagnostic_ceiling;
  bool load_failed;
  bool init_attempted;
  bool load_close_unknown;
  atomic_flag lifecycle;
  size_t live_children;
  pid_t original_process;
  bool closing;
  bool released;
  size_t live_easy_handles;
  bool tls_backend_pending;
  bool tls_owned;
  bool failed_init_cleanup_confirmed;
  const actql_http_component_tls_api *tls_api;
  actql_read_context *original_read;
  bool scoped_allocator;
  bool read_retained;
  bool init_owned;
  bool cleanup_threadsafe;
  actql_curl_global_cleanup_fn global_cleanup;
  int32_t test_path_copy_failure_at;
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
  int32_t diagnostic_ceiling;
  bool error_present;
  unsigned char *response;
  size_t response_length;
  size_t response_capacity;
  int64_t max_response_bytes;
  long connect_timeout_ms;
  long operation_timeout_ms;
  long status;
  atomic_bool cancelled;
  atomic_bool closed;
  atomic_bool credential_close_unknown;
  atomic_flag lifecycle;
  bool holder_counted;
  bool capacity_exceeded;
  bool constructor_failed;
  bool constructor_metadata_retired;
  int32_t test_retire_failures;
  int32_t test_retire_reply_losses;
} actql_native_http_client;

// Only realloc's original length is stored here. The existing Read/provider
// still owns allocation identity, overlap admission and pending retirement.
typedef union {
  max_align_t alignment;
  size_t bytes;
} actql_http_component_allocation;

static void *actql_http_component_allocate(void *read, void *lease, size_t bytes) {
  if (bytes > SIZE_MAX - sizeof(actql_http_component_allocation)) return NULL;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (!read || !lease || actql_native_owned_enter(lease) != 0) return NULL;
  if (actql_read_context_enter(read) != 0) {
    if (actql_native_owned_leave(lease) != 0) abort();
    return NULL;
  }
  // Resolver callbacks enter the SAME retained Read on their own thread. A
  // foreign current lease/Read refuses; neither entry creates a new grant.
  actql_http_component_allocation *header =
    actql_native_private_scoped_allocate(sizeof(*header) + bytes);
  if (actql_read_context_leave(read) != 0 || actql_native_owned_leave(lease) != 0) abort();
#else
  (void)read; (void)lease;
  actql_http_component_allocation *header = malloc(sizeof(*header) + bytes);
#endif
  if (!header) return NULL;
  header->bytes = bytes;
  return header + 1;
}

static actql_http_component_allocation *actql_http_component_header(void *read, void *lease, void *pointer) {
  actql_http_component_allocation *header = (actql_http_component_allocation *)pointer - 1;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  // Classify against the original physical provider before reading metadata.
  if (!read || !lease || actql_native_private_scoped_contains_allocation(read, lease, header, sizeof(*header)) != 0) abort();
  if (header->bytes > SIZE_MAX - sizeof(*header) ||
      actql_native_private_scoped_contains_allocation(read, lease, header, sizeof(*header) + header->bytes) != 0) abort();
#else
  (void)read; (void)lease;
#endif
  return header;
}

static void actql_http_component_retire(void *read, void *lease, void *pointer) {
  if (!pointer) return;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (!read || !lease || actql_native_owned_enter(lease) != 0) abort();
  if (actql_read_context_enter(read) != 0) abort();
#else
  (void)read;
#endif
  actql_http_component_allocation *header = actql_http_component_header(read, lease, pointer);
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  int status = actql_native_private_scoped_free(header);
  if (status != 0 && status != ACTQL_OWNED_BUSY && status != ACTQL_OWNED_PHYSICAL_FAILURE) abort();
  if (actql_read_context_leave(read) != 0 || actql_native_owned_leave(lease) != 0) abort();
#else
  free(header);
#endif
}

static void *actql_http_component_reallocate(void *read, void *lease, void *pointer, size_t bytes) {
  if (!pointer) return actql_http_component_allocate(read, lease, bytes);
  if (!bytes) { actql_http_component_retire(read, lease, pointer); return NULL; }
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (!read || !lease || actql_native_owned_enter(lease) != 0) return NULL;
  if (actql_read_context_enter(read) != 0) {
    if (actql_native_owned_leave(lease) != 0) abort();
    return NULL;
  }
#endif
  actql_http_component_allocation *header = actql_http_component_header(read, lease, pointer);
  void *replacement = actql_http_component_allocate(read, lease, bytes);
  if (replacement) {
    memcpy(replacement, pointer, header->bytes < bytes ? header->bytes : bytes);
    actql_http_component_retire(read, lease, pointer);
  }
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (actql_read_context_leave(read) != 0 || actql_native_owned_leave(lease) != 0) abort();
#endif
  return replacement;
}

static bool actql_http_read_current(actql_native_http_library *library) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return library && library->scoped_allocator && library->read_retained &&
    library->original_read && actql_bootstrap_current_read_context() == library->original_read;
#else
  return library != NULL;
#endif
}

static void *actql_http_allocate(actql_native_http_library *library, size_t bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return actql_http_read_current(library) ? actql_native_private_scoped_allocate(bytes) : NULL;
#else
  (void)library;
  return malloc(bytes);
#endif
}

static void actql_http_free(actql_native_http_library *library, void *pointer) {
  if (!pointer) return;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  // The existing provider classifies the exact original allocation after Read
  // leave as well. Pending physical extents stay in that provider's same Read;
  // returning an alias here cannot acknowledge the Read/domain/parent close.
  if (!library || !library->scoped_allocator || library->original_process != getpid()) abort();
  int status = actql_native_private_scoped_free(pointer);
  if (status != 0 && status != ACTQL_OWNED_BUSY && status != ACTQL_OWNED_PHYSICAL_FAILURE) abort();
#else
  (void)library;
  free(pointer);
#endif
}

static void *actql_http_reallocate(actql_native_http_library *library, void *pointer,
                                  size_t old_bytes, size_t bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  // Preserve the original while the complete replacement coexists. Refusal
  // leaves that original intact and never falls back to the stock allocator.
  void *replacement = actql_http_allocate(library, bytes);
  if (!replacement) return NULL;
  if (pointer) memcpy(replacement, pointer, old_bytes < bytes ? old_bytes : bytes);
  actql_http_free(library, pointer);
  return replacement;
#else
  (void)library; (void)old_bytes;
  return realloc(pointer, bytes);
#endif
}

static bool actql_http_release_read(actql_native_http_library *library) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (library->read_retained) {
    if (actql_read_context_release_after_owner_ack(library->original_read) != 0) return false;
    library->read_retained = false;
    library->original_read = NULL;
  }
#else
  (void)library;
#endif
  return true;
}

static void actql_http_library_lock(actql_native_http_library *library) {
  while (atomic_flag_test_and_set_explicit(&library->lifecycle, memory_order_acquire)) {}
}
static void actql_http_library_unlock(actql_native_http_library *library) {
  atomic_flag_clear_explicit(&library->lifecycle, memory_order_release);
}
static bool actql_http_library_current(actql_native_http_library *library) {
  return library && library->original_process == getpid() && library->dynamic_library && !library->load_failed &&
    !library->closing && !library->released && !library->load_close_unknown && actql_http_read_current(library);
}
static bool actql_http_retain_child(actql_native_http_library *library) {
  if (!library) return false;
  actql_http_library_lock(library);
  bool available = actql_http_library_current(library) && library->live_children != SIZE_MAX;
  if (available) library->live_children++;
  actql_http_library_unlock(library);
  return available;
}
static void actql_http_return_child(actql_native_http_client *client) {
  if (!client->holder_counted) return;
  actql_native_http_library *library = client->library;
  actql_http_library_lock(library);
  if (library->live_children == 0) abort();
  library->live_children--;
  client->holder_counted = false;
  actql_http_library_unlock(library);
}
static bool actql_http_begin_request(actql_native_http_client *client) {
  if (!client || atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire)) return false;
  actql_native_http_library *library = client->library;
  if (!library) { atomic_flag_clear_explicit(&client->lifecycle, memory_order_release); return false; }
  actql_http_library_lock(library);
  bool current = !client->closed && !client->constructor_failed &&
    !atomic_load_explicit(&client->credential_close_unknown, memory_order_relaxed) &&
    client->holder_counted && actql_http_library_current(library);
  actql_http_library_unlock(library);
  if (!current) atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return current;
}
static void actql_http_end_request(actql_native_http_client *client) {
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
}
static bool actql_http_transport_entry(actql_native_http_client *client) {
  actql_native_http_library *library = client->library;
  actql_http_library_lock(library);
  bool current = actql_http_library_current(library);
  actql_http_library_unlock(library);
  return current;
}

static CURL *actql_http_create_easy(actql_native_http_client *client) {
  actql_native_http_library *library = client->library;
  actql_http_library_lock(library);
  bool current = actql_http_library_current(library) && library->live_easy_handles != SIZE_MAX;
  if (current) library->live_easy_handles++;
  actql_http_library_unlock(library);
  if (!current) return NULL;
  CURL *easy = library->easy_init();
  if (!easy) {
    actql_http_library_lock(library);
    library->live_easy_handles--;
    actql_http_library_unlock(library);
  }
  return easy;
}

static void actql_http_cleanup_easy(actql_native_http_client *client, CURL *easy) {
  actql_native_http_library *library = client->library;
  // Keep the original handle counted until cleanup actually returns. Requests
  // require QUICK_EXIT=0 below: their private easy-interface multi handle joins
  // its resolver workers instead of detaching them. Configuration alone, the
  // perform result, cancellation and global_cleanup are not this completion.
  library->easy_cleanup(easy);
  if (library->tls_api && library->tls_owned) library->tls_api->cleanup_thread();
  actql_http_library_lock(library);
  if (library->live_easy_handles == 0) abort();
  library->live_easy_handles--;
  actql_http_library_unlock(library);
}
static int32_t actql_http_close_library(actql_native_http_library *library) {
  if (!library || library->original_process != getpid()) return -1;
  actql_http_library_lock(library);
  int32_t status = 0;
  if (library->load_close_unknown) status = -3;
  else if (library->released) status = 0;
  else if (library->load_failed || !library->dynamic_library) status = -1;
  else {
    library->closing = true;
    if (library->live_children != 0 || library->live_easy_handles != 0) status = -2;
    else if (!library->cleanup_threadsafe || !library->global_cleanup) status = -3;
    else {
      // All original Client holders and actual easy cleanup calls have now
      // retired. Balance only this successful init reference. Global cleanup
      // is not substituted for the preceding per-handle resolver teardown.
      if (library->init_owned) {
        library->global_cleanup();
        library->init_owned = false;
      }
      // The original TLS image balances its own Library references. Missing
      // backend cleanup remains pending even before the first transfer: TLS
      // initialization itself can own global and thread-local resources.
      if (library->tls_backend_pending) {
        if (!library->tls_owned || !library->tls_api || library->tls_api->release() != 0)
          status = -3;
        else {
          library->tls_owned = false;
          library->tls_backend_pending = false;
        }
      }
      if (status != 0) { /* Keep the same init/module custody on uncertainty. */ }
      else if (dlclose(library->dynamic_library) != 0) {
        library->load_close_unknown = true;
        status = -3;
      } else {
        library->dynamic_library = NULL;
        library->released = true;
      }
    }
  }
  if (status == 0 && library->released) {
    actql_http_free(library, library->error);
    library->error = NULL;
    if (!actql_http_release_read(library)) status = -3;
  }
  actql_http_library_unlock(library);
  return status;
}

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
  actql_native_http_library *library, char **target, int32_t ceiling, const char *message
) {
  actql_http_free(library, *target);
  *target = NULL;
  size_t length;
  if (!actql_diagnostic_length(message, ceiling, &length)) return;
  char *copy = actql_http_allocate(library, length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length);
  copy[length] = '\0';
  *target = copy;
}

// The original error fact is distinct from fallible diagnostic storage.
static void actql_set_client_error(
  actql_native_http_client *client, const char *message
) {
  actql_native_http_library *library = client ? client->library : NULL;
  client->error_present = message != NULL;
  actql_replace_error(library, &client->error, client->diagnostic_ceiling, message);
}

static char *actql_copy_text(actql_native_http_library *library, moonbit_bytes_t bytes, int32_t length) {
  if (length <= 0 || memchr(bytes, 0, (size_t)length) != NULL) return NULL;
  char *text = actql_http_allocate(library, (size_t)length + 1);
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

static moonbit_bytes_t actql_copy_diagnostic(const char *text, int32_t ceiling) {
  size_t length;
  if (!actql_diagnostic_length(text, ceiling, &length) || length > INT32_MAX)
    return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(text, length);
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
  actql_replace_error(library, &library->error, library->diagnostic_ceiling, error == NULL ? name : error);
  return false;
}

#define ACTQL_LOAD(library, field, symbol) \
  actql_load_symbol((library), (void **)&((library)->field), (symbol))

int32_t actql_native_http_retire_failed_library(actql_native_http_library *library);

static void actql_native_http_library_finalize(void *value) {
  actql_native_http_library *library = value;
  if (!library->load_failed) {
    // Explicit caller custody is required for pending retirement. Finalization
    // never invents global/loader/thread ACK or repeats an unknown close.
    (void)actql_http_close_library(library);
  } else {
    // Best effort only: use the same process fence and serialized failed
    // original as explicit cleanup. Finalization issues no caller ACK.
    (void)actql_native_http_retire_failed_library(library);
  }
  actql_http_free(library, library->error);
  library->error = NULL;
}

static void actql_clear_response(actql_native_http_client *client) {
  actql_native_http_library *library = client ? client->library : NULL;
  actql_http_free(library, client->response);
  client->response = NULL;
  client->response_length = 0;
  client->response_capacity = 0;
  client->status = 0;
  client->capacity_exceeded = false;
  actql_set_client_error(client, NULL);
}

static void actql_native_http_client_finalize(void *value) {
  actql_native_http_client *client = value;
  actql_native_http_library *library = client ? client->library : NULL;
  actql_http_free(library, client->ca_path);
  actql_http_free(library, client->certificate_path);
  actql_http_free(library, client->key_path);
  actql_http_free(library, client->bearer_path);
  actql_http_free(library, client->error);
  actql_http_free(library, client->response);
  client->ca_path = NULL;
  client->certificate_path = NULL;
  client->key_path = NULL;
  client->bearer_path = NULL;
  client->error = NULL;
  client->response = NULL;
  if (client->library != NULL) {
    // An unobserved descriptor close cannot be retried using its consumed
    // number. Finalization must not erase the Library's original obligation.
    if (!atomic_load_explicit(&client->credential_close_unknown, memory_order_relaxed))
      actql_http_return_child(client);
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
  actql_native_http_library *library = client ? client->library : NULL;
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
    unsigned char *expanded = actql_http_reallocate(library, client->response, client->response_capacity, capacity);
    if (expanded == NULL) {
      actql_set_client_error(client, "HTTP response allocation failed");
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
  (void)curl;
  if (code == ACTQL_CURLE_OK) return true;
  const char *detail = client->library->easy_strerror(code);
  actql_set_client_error(client, detail == NULL ? operation : detail);
  return false;
}

static bool actql_http_same_image(void *left, void *right) {
  Dl_info a, b;
  return dladdr(left, &a) != 0 && dladdr(right, &b) != 0 && a.dli_fbase == b.dli_fbase;
}

// The issue-only loader still owns its exact module reference on rejection.
// Losing that close observation must not let later failed cleanup return the
// parent Read. The consumed handle is never retried on uncertainty.
static void actql_http_close_rejected_loader_reference(
  actql_native_http_library *library
) {
  if (dlclose(library->dynamic_library) != 0)
    library->load_close_unknown = true;
  else
    library->dynamic_library = NULL;
}

static void *actql_native_http_load_library_impl(
  moonbit_bytes_t path,
  int32_t length,
  int32_t diagnostic_ceiling,
  bool retain_failed
) {
  actql_native_http_library *library = moonbit_make_external_object(
    actql_native_http_library_finalize,
    sizeof(actql_native_http_library)
  );
  memset(library, 0, sizeof(*library));
  atomic_flag_clear(&library->lifecycle);
  library->original_process = getpid();
  library->diagnostic_ceiling = diagnostic_ceiling;
  library->load_failed = true;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  library->scoped_allocator = true;
  library->original_read = actql_bootstrap_current_read_context();
  if (!library->original_read || actql_read_context_retain(library->original_read) != 0)
    return library;
  library->read_retained = true;
#endif
  char *path_text = actql_copy_text(library, path, length);
  if (path_text == NULL) {
    actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP library path is invalid");
    return library;
  }
  library->dynamic_library = dlopen(path_text, RTLD_NOW | RTLD_LOCAL);
  actql_http_free(library, path_text);
  if (library->dynamic_library == NULL) {
    actql_replace_error(library, &library->error, library->diagnostic_ceiling, dlerror());
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
    if (!retain_failed) {
      actql_http_close_rejected_loader_reference(library);
    }
    return library;
  }
  actql_http_component_tls_api_fn tls_api = (actql_http_component_tls_api_fn)dlsym(
    library->dynamic_library, "curl_actql_native_tls_api_v3");
  if (tls_api) {
    if (!actql_http_same_image((void *)tls_api, (void *)library->global_init)) {
      actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP TLS component image differs");
      return library;
    }
    const actql_http_component_tls_api *api = tls_api();
    if (!api || api->abi != 3 || api->bytes != sizeof(*api) ||
        !api->acquire || !api->cleanup_thread || !api->release ||
        !api->allocate || !api->retire || !api->reallocate || !api->duplicate || !api->allocate_zeroed ||
        !actql_http_same_image((void *)api, (void *)tls_api) ||
        !actql_http_same_image((void *)api->acquire, (void *)tls_api) ||
        !actql_http_same_image((void *)api->cleanup_thread, (void *)tls_api) ||
        !actql_http_same_image((void *)api->release, (void *)tls_api) ||
        !actql_http_same_image((void *)api->allocate, (void *)tls_api) ||
        !actql_http_same_image((void *)api->retire, (void *)tls_api) ||
        !actql_http_same_image((void *)api->reallocate, (void *)tls_api) ||
        !actql_http_same_image((void *)api->duplicate, (void *)tls_api) ||
        !actql_http_same_image((void *)api->allocate_zeroed, (void *)tls_api)) {
      actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP TLS component acquisition refused");
      return library;
    }
    actql_http_component_memory memory = {
      library->original_read,
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
      actql_native_owned_current(),
#else
      NULL,
#endif
      actql_http_component_allocate, actql_http_component_reallocate, actql_http_component_retire
    };
    int acquisition = api->acquire(&memory);
    if (acquisition < 0) {
      actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP original Read binding refused");
      return library;
    }
    library->tls_api = api;
    library->tls_owned = true;
    if (acquisition != 0) {
      // The failed TLS constructor still owns the original reference and its
      // partial allocations. Only failed-custody retirement may release it.
      library->init_attempted = true;
      actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP TLS initialization failed");
      return library;
    }
  }
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (!library->tls_owned) {
    actql_replace_error(library, &library->error, library->diagnostic_ceiling, "HTTP component lacks original Read allocator binding");
    return library;
  }
#endif
  library->init_attempted = true;
  actql_curl_global_init_mem_fn init_mem = (actql_curl_global_init_mem_fn)dlsym(
    library->dynamic_library, "curl_global_init_mem");
  CURLcode code = library->tls_owned
    ? (init_mem && actql_http_same_image((void *)init_mem, (void *)library->global_init)
      ? init_mem(ACTQL_CURL_GLOBAL_ALL, library->tls_api->allocate, library->tls_api->retire,
          library->tls_api->reallocate, library->tls_api->duplicate, library->tls_api->allocate_zeroed)
      : 2)
    : library->global_init(ACTQL_CURL_GLOBAL_ALL);
  if (library->tls_owned) library->tls_api->cleanup_thread();
  if (code != ACTQL_CURLE_OK) {
    actql_replace_error(library, &library->error, library->diagnostic_ceiling, library->easy_strerror(code));
    if (library->tls_owned && library->tls_api->release() == 0) {
      library->tls_owned = false;
      library->failed_init_cleanup_confirmed = true;
    }
    if (!retain_failed && library->failed_init_cleanup_confirmed) {
      actql_http_close_rejected_loader_reference(library);
    }
  } else {
    library->load_failed = false;
    library->init_owned = true;
    library->tls_backend_pending = true;
    library->global_cleanup = (actql_curl_global_cleanup_fn)dlsym(library->dynamic_library, "curl_global_cleanup");
    actql_curl_version_info_fn version_info = (actql_curl_version_info_fn)dlsym(library->dynamic_library, "curl_version_info");
    const actql_curl_version_info *info = version_info ? version_info(0) : NULL;
    library->cleanup_threadsafe = info && (info->features & ACTQL_CURL_VERSION_THREADSAFE) != 0;
  }
  return library;
}


void *actql_native_http_load_library(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling
) {
  return actql_native_http_load_library_impl(path, length, diagnostic_ceiling, false);
}

void *actql_native_http_load_library_with_custody(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling
) {
  return actql_native_http_load_library_impl(path, length, diagnostic_ceiling, true);
}

// Only a rejected load, before successful runtime admission. This does not
// close a usable Library or infer resolver-thread/global-init retirement.
static int32_t actql_native_http_retire_failed_library_owned(actql_native_http_library *library) {
  if (library == NULL || library->original_process != getpid() || !library->load_failed) return -1;
  if (library->load_close_unknown) return -2;
  if (library->dynamic_library != NULL) {
    if (library->init_attempted && !library->failed_init_cleanup_confirmed &&
        library->tls_owned && library->tls_api->release() == 0) {
      library->tls_owned = false;
      library->failed_init_cleanup_confirmed = true;
    }
    if (library->init_attempted && !library->failed_init_cleanup_confirmed) return -2;
    if (dlclose(library->dynamic_library) != 0) {
      library->load_close_unknown = true;
      return -2;
    }
    library->dynamic_library = NULL;
  }
  actql_http_free(library, library->error);
  library->error = NULL;
  return actql_http_release_read(library) ? 0 : -2;
}


// Serialize the SAME failed original with the ready lifetime path. A second
// cleanup observes the recorded result, never a concurrently consumed handle.
int32_t actql_native_http_retire_failed_library(actql_native_http_library *library) {
  if (!library || library->original_process != getpid()) return -1;
  actql_http_library_lock(library);
  int32_t result = actql_native_http_retire_failed_library_owned(library);
  actql_http_library_unlock(library);
  return result;
}

// Independent fault setup: actual unload, missing observation. Future calls
// must retain pending instead of reusing/reclosing the consumed handle.
int32_t actql_native_http_test_lose_failed_library_close(actql_native_http_library *library) {
  if (!library || library->original_process != getpid()) return -1;
  actql_http_library_lock(library);
  int32_t result = -1;
  if (library->load_failed && !library->init_attempted && library->dynamic_library && !library->load_close_unknown) {
    if (dlclose(library->dynamic_library) == 0) { library->load_close_unknown = true; result = 0; }
  }
  actql_http_library_unlock(library);
  return result;
}

int32_t actql_native_http_library_ready(
  actql_native_http_library *library
) {
  if (!library) return false;
  actql_http_library_lock(library);
  bool current = actql_http_library_current(library);
  actql_http_library_unlock(library);
  return current;
}

int32_t actql_native_http_library_close_checked(actql_native_http_library *library) {
  return actql_http_close_library(library);
}

int64_t actql_native_http_test_live_children(actql_native_http_library *library) {
  if (!library) return -1;
  actql_http_library_lock(library);
  int64_t count = library->live_children > INT64_MAX ? -1 : (int64_t)library->live_children;
  actql_http_library_unlock(library);
  return count;
}

moonbit_bytes_t actql_native_http_library_error(actql_native_http_library *library) {
  return library == NULL ? actql_copy_bytes(NULL, 0) :
    actql_copy_diagnostic(library->error, library->diagnostic_ceiling);
}

moonbit_bytes_t actql_native_http_library_version(actql_native_http_library *library) {
  if (!library) return actql_copy_message("");
  actql_http_library_lock(library);
  moonbit_bytes_t result = actql_copy_message(actql_http_library_current(library) ? library->version() : "");
  actql_http_library_unlock(library);
  return result;
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
static bool actql_read_bearer_authorization(actql_native_http_client *client,
  const char *path,
  actql_native_private_file_projection *projection,
  size_t max_bytes,
  bool strict,
  char **authorization_out,
  size_t *authorization_length_out
) {
  actql_native_http_library *library = client->library;
  *authorization_out = NULL;
  *authorization_length_out = 0;
  enum { ACTQL_BEARER_BUFFER_BYTES = 8192 };
  if ((path == NULL && projection == NULL) || max_bytes == 0 ||
      max_bytes > ACTQL_BEARER_BUFFER_BYTES) {
    return false;
  }
  struct stat expected_secret;
  bool secret_generation_valid =
    projection != NULL ||
    (lstat(path, &expected_secret) == 0 && S_ISREG(expected_secret.st_mode));
  int descriptor = -1;
  if (projection != NULL) {
    // A rejected generation may still have acquired the original descriptor.
    // Keep that partial on this same Client until its close is observed.
    secret_generation_valid = actql_native_private_file_projection_open_with_custody(
      projection, &descriptor
    );
  } else if (secret_generation_valid) {
    descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  }
  if (descriptor < 0) return false;
  unsigned char secret[ACTQL_BEARER_BUFFER_BYTES + 1];
  size_t secret_length = 0;
  struct stat opened_secret;
  bool secret_valid = secret_generation_valid && fstat(descriptor, &opened_secret) == 0 &&
    S_ISREG(opened_secret.st_mode) &&
    (projection != NULL
      ? actql_native_private_file_projection_matches(projection, descriptor)
      : actql_same_file_generation(&expected_secret, &opened_secret)) &&
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
  if (!secret_valid || fstat(descriptor, &completed_secret) != 0 ||
      !actql_same_file_generation(&opened_secret, &completed_secret) ||
      (projection != NULL &&
       !actql_native_private_file_projection_matches(projection, descriptor))) {
    secret_valid = false;
  }
  if (close(descriptor) != 0) {
    // Keep the same Client/Library pending. A later request or GC cannot
    // establish whether this original descriptor retired, nor retry its number.
    atomic_store_explicit(&client->credential_close_unknown, true, memory_order_relaxed);
    secret_valid = false;
  }
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
    ? actql_http_allocate(library, authorization_length + 1)
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

static void actql_forget_authorization(actql_native_http_library *library, char *authorization, size_t length) {
  if (authorization == NULL) return;
  memset(authorization, 0, length);
  actql_http_free(library, authorization);
}

static void actql_set_client_constructor_error(
  actql_native_http_client *client, const char *message
) {
  client->constructor_failed = true;
  actql_set_client_error(client, message);
}

static char *actql_copy_constructor_path(
  actql_native_http_library *library, moonbit_bytes_t bytes, int32_t length
) {
  if (library != NULL && library->test_path_copy_failure_at > 0 &&
      --library->test_path_copy_failure_at == 0) return NULL;
  return actql_copy_text(library, bytes, length);
}

void actql_native_http_test_fail_constructor_path(
  actql_native_http_library *library, int32_t occurrence
) {
  if (library != NULL) library->test_path_copy_failure_at = occurrence;
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
  atomic_init(&client->closed, false);
  atomic_init(&client->credential_close_unknown, false);
  atomic_flag_clear(&client->lifecycle);
  client->library = library;
  client->holder_counted = actql_http_retain_child(library);
  client->diagnostic_ceiling = library == NULL ? 0 : library->diagnostic_ceiling;
  if (library != NULL) moonbit_incref(library);
  client->max_response_bytes = max_response_bytes;
  client->connect_timeout_ms = connect_timeout_ms;
  client->operation_timeout_ms = operation_timeout_ms;
  if (!client->holder_counted ||
      max_response_bytes < 0 || max_response_bytes > INT32_MAX ||
      connect_timeout_ms <= 0 || operation_timeout_ms < connect_timeout_ms) {
    actql_set_client_constructor_error(client, "invalid HTTP client configuration");
    return client;
  }
  client->ca_path = actql_copy_constructor_path(library, ca_path, ca_path_length);
  client->certificate_path = actql_copy_constructor_path(
    library, certificate_path,
    certificate_path_length
  );
  client->key_path = actql_copy_constructor_path(library, key_path, key_path_length);
  if (client->ca_path == NULL || client->certificate_path == NULL ||
      client->key_path == NULL) {
    actql_set_client_constructor_error(client, "HTTP credential path allocation failed");
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
  atomic_init(&client->closed, false);
  atomic_init(&client->credential_close_unknown, false);
  atomic_flag_clear(&client->lifecycle);
  client->library = library;
  client->holder_counted = actql_http_retain_child(library);
  client->diagnostic_ceiling = library == NULL ? 0 : library->diagnostic_ceiling;
  if (library != NULL) moonbit_incref(library);
  client->max_response_bytes = max_response_bytes;
  client->connect_timeout_ms = connect_timeout_ms;
  client->operation_timeout_ms = operation_timeout_ms;
  bool mutual = certificate_path_length > 0 || key_path_length > 0;
  bool bearer = bearer_path_length > 0;
  if (!client->holder_counted ||
      max_response_bytes < 0 || max_response_bytes > INT32_MAX ||
      connect_timeout_ms <= 0 || operation_timeout_ms < connect_timeout_ms ||
      (!mutual && !bearer) ||
      (mutual && (certificate_path_length <= 0 || key_path_length <= 0))) {
    actql_set_client_constructor_error(client, "invalid HTTP client configuration");
    return client;
  }
  client->ca_path = actql_copy_constructor_path(library, ca_path, ca_path_length);
  if (mutual) {
    client->certificate_path = actql_copy_constructor_path(
      library, certificate_path,
      certificate_path_length
    );
    client->key_path = actql_copy_constructor_path(library, key_path, key_path_length);
  }
  if (bearer) {
    client->bearer_path = actql_copy_constructor_path(library, bearer_path, bearer_path_length);
  }
  if (client->ca_path == NULL ||
      (mutual && (client->certificate_path == NULL ||
        client->key_path == NULL)) ||
      (bearer && client->bearer_path == NULL)) {
    actql_set_client_constructor_error(client, "HTTP credential path allocation failed");
  }
  return client;
}

int32_t actql_native_http_client_ready(actql_native_http_client *client) {
  if (!client || !client->library) return false;
  actql_http_library_lock(client->library);
  bool current = actql_http_library_current(client->library);
  if (!current && !client->closed && !client->constructor_failed)
    actql_set_client_constructor_error(client, "original HTTP Library closing or unavailable");
  bool ready = current && client->holder_counted && !client->error_present && !client->closed &&
    !atomic_load_explicit(&client->credential_close_unknown, memory_order_relaxed);
  actql_http_library_unlock(client->library);
  return ready;
}

moonbit_bytes_t actql_native_http_client_error(actql_native_http_client *client) {
  if (!client || atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire))
    return actql_copy_bytes(NULL, 0);
  moonbit_bytes_t result = actql_copy_diagnostic(client->error, client->diagnostic_ceiling);
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return result;
}

static int32_t actql_native_http_client_post_json_owned(
  actql_native_http_client *client,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t body,
  int32_t body_length
) {
  actql_native_http_library *library = client ? client->library : NULL;
  if (client == NULL || client->closed) return 3;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return 2;
  actql_clear_response(client);
  char *url_text = actql_copy_text(library, url, url_length);
  if (url_text == NULL) {
    actql_set_client_error(client, "invalid HTTPS URL");
    return -1;
  }
  char *authorization = NULL;
  size_t authorization_length = 0;
  if (client->bearer_path != NULL &&
      !actql_read_bearer_authorization(client,
        client->bearer_path,
        NULL,
        ACTQL_BEARER_FILE_MAX_BYTES,
        true,
        &authorization,
        &authorization_length
      )) {
    actql_http_free(library, url_text);
    actql_set_client_error(client, "bearer credential unavailable");
    return 5;
  }
  CURL *curl = actql_http_create_easy(client);
  if (curl == NULL) {
    actql_forget_authorization(library, authorization, authorization_length);
    actql_http_free(library, url_text);
    actql_set_client_error(client, "initialize HTTP request failed");
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
      actql_set_client_error(client, "HTTP header allocation failed");
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
      actql_set_client_error(client, "HTTP header allocation failed");
    } else {
      headers = next_headers;
    }
  }
  actql_forget_authorization(library, authorization, authorization_length);
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
  ACTQL_SET(ACTQL_CURLOPT_QUICK_EXIT, 0L);
  ACTQL_SET(ACTQL_CURLOPT_CONNECTTIMEOUT_MS, client->connect_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_TIMEOUT_MS, client->operation_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_WRITEFUNCTION, actql_receive_response);
  ACTQL_SET(ACTQL_CURLOPT_WRITEDATA, client);
  ACTQL_SET(ACTQL_CURLOPT_NOPROGRESS, 0L);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFOFUNCTION, actql_transfer_progress);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFODATA, client);
#undef ACTQL_SET
  if (configured && !actql_http_transport_entry(client)) configured = false;
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
  if (code != ACTQL_CURLE_OK && !client->error_present &&
      !client->capacity_exceeded &&
      !atomic_load_explicit(&client->cancelled, memory_order_relaxed)) {
    const char *message = error_buffer[0] == '\0'
      ? client->library->easy_strerror(code)
      : error_buffer;
    actql_set_client_error(client, message);
  }
  client->library->slist_free_all(headers);
  actql_http_cleanup_easy(client, curl);
  actql_http_free(library, url_text);
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
  bool has_bearer,
  bool *valid
) {
  actql_native_http_library *library = client ? client->library : NULL;
  *valid = false;
  if (length < 0 || length > 32768) {
    actql_set_client_error(client, "invalid HTTP header block");
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
    if (has_bearer && colon - offset == 13 &&
        memcmp(block + offset, "authorization", 13) == 0) goto invalid;
    for (int32_t index = colon + 2; index < end; index += 1) {
      if (block[index] < 32 || block[index] > 126) goto invalid;
    }
    size_t line_length = (size_t)(end - offset);
    char *line = actql_http_allocate(library, line_length + 1);
    if (line == NULL) {
      actql_set_client_error(client, "HTTP header allocation failed");
      client->library->slist_free_all(headers);
      return NULL;
    }
    memcpy(line, block + offset, line_length);
    line[line_length] = '\0';
    curl_slist *next = client->library->slist_append(headers, line);
    actql_http_free(library, line);
    if (next == NULL) {
      actql_set_client_error(client, "HTTP header allocation failed");
      client->library->slist_free_all(headers);
      return NULL;
    }
    headers = next;
    offset = end + 1;
  }
  *valid = true;
  return headers;

invalid:
  actql_set_client_error(client, "invalid HTTP header block");
  client->library->slist_free_all(headers);
  return NULL;
}

static bool actql_http_credential_deadline_current(int64_t expires_at) {
  struct timespec observed_time;
  return expires_at > 0 && clock_gettime(CLOCK_REALTIME, &observed_time) == 0 &&
    observed_time.tv_sec >= 0 && observed_time.tv_sec <= INT64_MAX / 1000 &&
    observed_time.tv_sec * 1000 + observed_time.tv_nsec / 1000000 < expires_at;
}

static int32_t actql_native_http_client_request_owned(
  actql_native_http_client *client,
  moonbit_bytes_t method,
  int32_t method_length,
  moonbit_bytes_t url,
  int32_t url_length,
  moonbit_bytes_t headers_block,
  int32_t headers_length,
  moonbit_bytes_t body,
  int32_t body_length,
  const char *bearer_path,
  actql_native_private_file_projection *preparation_projection,
  bool require_deadline,
  int64_t expires_at_milliseconds
) {
  actql_native_http_library *library = client ? client->library : NULL;
  if (client == NULL || client->closed) return 3;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return 2;
  actql_clear_response(client);
  char *method_text = actql_copy_text(library, method, method_length);
  char *url_text = actql_copy_text(library, url, url_length);
  bool is_get = method_text != NULL && strcmp(method_text, "GET") == 0;
  bool is_post = method_text != NULL && strcmp(method_text, "POST") == 0;
  bool is_put = method_text != NULL && strcmp(method_text, "PUT") == 0;
  bool is_patch = method_text != NULL && strcmp(method_text, "PATCH") == 0;
  if (url_text == NULL || (!is_get && !is_post && !is_put && !is_patch) ||
      body_length < 0 || (is_get && body_length != 0) ||
      (preparation_projection != NULL && (!is_get || !require_deadline))) {
    actql_http_free(library, method_text);
    actql_http_free(library, url_text);
    actql_set_client_error(client, "invalid HTTPS request");
    return -1;
  }
  bool headers_valid = false;
  curl_slist *headers = actql_http_headers_from_block(
    client,
    headers_block,
    headers_length,
    bearer_path != NULL || preparation_projection != NULL,
    &headers_valid
  );
  if (!headers_valid) {
    actql_http_free(library, method_text);
    actql_http_free(library, url_text);
    return 6;
  }
  if (bearer_path != NULL || preparation_projection != NULL) {
    char *authorization = NULL;
    size_t authorization_length = 0;
    if (!actql_read_bearer_authorization(client,
          bearer_path,
          preparation_projection,
          require_deadline ? 8192 : ACTQL_BEARER_FILE_MAX_BYTES,
          preparation_projection != NULL || !require_deadline,
          &authorization,
          &authorization_length
        )) {
      client->library->slist_free_all(headers);
      actql_http_free(library, method_text);
      actql_http_free(library, url_text);
      actql_set_client_error(client, "bearer credential unavailable");
      return 5;
    }
    curl_slist *next_headers = client->library->slist_append(
      headers,
      authorization
    );
    actql_forget_authorization(library, authorization, authorization_length);
    if (next_headers == NULL) {
      client->library->slist_free_all(headers);
      actql_http_free(library, method_text);
      actql_http_free(library, url_text);
      actql_set_client_error(client, "HTTP header allocation failed");
      return -1;
    }
    headers = next_headers;
  }
  if (require_deadline) {
    bool deadline_valid = actql_http_credential_deadline_current(
      expires_at_milliseconds
    );
    if (!deadline_valid) {
      client->library->slist_free_all(headers);
      actql_http_free(library, method_text);
      actql_http_free(library, url_text);
      actql_set_client_error(client, "credential deadline expired");
      return 4;
    }
  }
  CURL *curl = actql_http_create_easy(client);
  if (curl == NULL) {
    client->library->slist_free_all(headers);
    actql_http_free(library, method_text);
    actql_http_free(library, url_text);
    actql_set_client_error(client, "initialize HTTP request failed");
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
    if (is_put || is_patch) ACTQL_SET(ACTQL_CURLOPT_CUSTOMREQUEST, method_text);
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
  ACTQL_SET(ACTQL_CURLOPT_QUICK_EXIT, 0L);
  ACTQL_SET(ACTQL_CURLOPT_CONNECTTIMEOUT_MS, client->connect_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_TIMEOUT_MS, client->operation_timeout_ms);
  ACTQL_SET(ACTQL_CURLOPT_WRITEFUNCTION, actql_receive_response);
  ACTQL_SET(ACTQL_CURLOPT_WRITEDATA, client);
  ACTQL_SET(ACTQL_CURLOPT_NOPROGRESS, 0L);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFOFUNCTION, actql_transfer_progress);
  ACTQL_SET(ACTQL_CURLOPT_XFERINFODATA, client);
#undef ACTQL_SET
  // Recheck the original installation after configuration, immediately before
  // entering transport. This never adopts a newly replaced credential file.
  if (configured && preparation_projection != NULL) {
    int descriptor = -1;
    bool current_installation = actql_native_private_file_projection_open_with_custody(
      preparation_projection, &descriptor
    );
    if (descriptor >= 0 && close(descriptor) != 0) {
      // This second original credential descriptor has the same physical
      // retirement duty as the earlier body reader. Refusing transport alone
      // cannot let Client/Library close acknowledge its unobserved close.
      atomic_store_explicit(&client->credential_close_unknown, true, memory_order_relaxed);
      current_installation = false;
    }
    bool current_deadline = actql_http_credential_deadline_current(
      expires_at_milliseconds
    );
    bool cancelled = atomic_load_explicit(&client->cancelled, memory_order_relaxed);
    if (!current_installation || !current_deadline || cancelled) {
      client->library->slist_free_all(headers);
      actql_http_cleanup_easy(client, curl);
      actql_http_free(library, method_text);
      actql_http_free(library, url_text);
      actql_set_client_error(client, !current_installation
        ? "bearer credential unavailable" : !current_deadline
        ? "credential deadline expired" : "HTTP request cancelled");
      return !current_installation ? 5 : !current_deadline ? 4 : 2;
    }
  }
  if (configured && !actql_http_transport_entry(client)) configured = false;
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
  if (code != ACTQL_CURLE_OK && !client->error_present &&
      !client->capacity_exceeded &&
      !atomic_load_explicit(&client->cancelled, memory_order_relaxed)) {
    const char *message = error_buffer[0] == '\0'
      ? client->library->easy_strerror(code)
      : error_buffer;
    actql_set_client_error(client, message);
  }
  client->library->slist_free_all(headers);
  actql_http_cleanup_easy(client, curl);
  actql_http_free(library, method_text);
  actql_http_free(library, url_text);
  if (client->capacity_exceeded) return 1;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed) ||
      code == ACTQL_CURLE_ABORTED_BY_CALLBACK) return 2;
  return code == ACTQL_CURLE_OK ? 0 : -1;
}

int32_t actql_native_http_client_post_json(
  actql_native_http_client *client, moonbit_bytes_t url, int32_t url_length,
  moonbit_bytes_t body, int32_t body_length
) {
  if (!actql_http_begin_request(client)) return 3;
  int32_t result = actql_native_http_client_post_json_owned(client, url, url_length, body, body_length);
  actql_http_end_request(client);
  return result;
}

int32_t actql_native_http_client_request(
  actql_native_http_client *client,
  moonbit_bytes_t method, int32_t method_length,
  moonbit_bytes_t url, int32_t url_length,
  moonbit_bytes_t headers, int32_t headers_length,
  moonbit_bytes_t body, int32_t body_length
) {
  if (!actql_http_begin_request(client)) return 3;
  int32_t result = actql_native_http_client_request_owned(client, method, method_length,
    url, url_length, headers, headers_length, body, body_length, client->bearer_path, NULL, false, 0);
  actql_http_end_request(client);
  return result;
}

int32_t actql_native_http_client_request_bearer_file(
  actql_native_http_client *client,
  moonbit_bytes_t method, int32_t method_length,
  moonbit_bytes_t url, int32_t url_length,
  moonbit_bytes_t headers, int32_t headers_length,
  moonbit_bytes_t body, int32_t body_length,
  moonbit_bytes_t secret_path, int32_t secret_path_length,
  int64_t expires_at_milliseconds
) {
  actql_native_http_library *library = client ? client->library : NULL;
  if (!actql_http_begin_request(client)) return 3;
  char *path = actql_copy_text(library, secret_path, secret_path_length);
  int32_t result = path ? actql_native_http_client_request_owned(client, method, method_length,
    url, url_length, headers, headers_length, body, body_length, path, NULL, true, expires_at_milliseconds) : 6;
  actql_http_free(library, path);
  actql_http_end_request(client);
  return result;
}

int32_t actql_native_http_client_get_local_preparation(
  actql_native_http_client *client,
  moonbit_bytes_t method, int32_t method_length,
  moonbit_bytes_t url, int32_t url_length,
  moonbit_bytes_t headers, int32_t headers_length,
  moonbit_bytes_t body, int32_t body_length,
  actql_native_private_file_projection *projection, int64_t expires_at_milliseconds
) {
  if (!actql_http_begin_request(client)) return 3;
  int32_t result = projection ? actql_native_http_client_request_owned(client, method, method_length,
    url, url_length, headers, headers_length, body, body_length, NULL, projection, true, expires_at_milliseconds) : 5;
  actql_http_end_request(client);
  return result;
}

int64_t actql_native_http_client_response_limit(actql_native_http_client *client) {
  if (client == NULL || client->library == NULL ||
      client->max_response_bytes < 0 || client->max_response_bytes > INT32_MAX) {
    return -2;
  }
  if (client->closed) return -1;
  if (atomic_load_explicit(&client->cancelled, memory_order_relaxed)) return -3;
  return client->max_response_bytes;
}

int32_t actql_native_http_client_status(actql_native_http_client *client) {
  if (!client || atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire)) return 0;
  int32_t result = client->status < 0 || client->status > INT32_MAX ? 0 : (int32_t)client->status;
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return result;
}

moonbit_bytes_t actql_native_http_client_body(actql_native_http_client *client) {
  if (!client || atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire))
    return actql_copy_bytes(NULL, 0);
  moonbit_bytes_t result = actql_copy_bytes(client->response, client->response_length);
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return result;
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
  actql_native_http_library *library = client ? client->library : NULL;
  if (!client || !client->library || client->library->original_process != getpid() || client->constructor_failed) return false;
  atomic_store_explicit(&client->cancelled, true, memory_order_relaxed);
  if (atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire)) return false;
  if (atomic_load_explicit(&client->credential_close_unknown, memory_order_relaxed)) {
    atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
    return false;
  }
  bool closed = !client->closed;
  if (closed) {
    client->closed = true;
    actql_http_free(library, client->ca_path); actql_http_free(library, client->certificate_path); actql_http_free(library, client->key_path); actql_http_free(library, client->bearer_path);
    client->ca_path = NULL; client->certificate_path = NULL; client->key_path = NULL; client->bearer_path = NULL;
    actql_clear_response(client);
    actql_http_return_child(client);
  }
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return closed;
}


int32_t actql_native_http_client_close_checked(actql_native_http_client *client) {
  if (!client || !client->library || client->library->original_process != getpid() || client->constructor_failed) return -1;
  atomic_store_explicit(&client->cancelled, true, memory_order_relaxed);
  if (atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire)) return -1;
  bool done = client->closed && !client->holder_counted;
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  if (done) return 0;
  return actql_native_http_client_close(client) ? 0 : -1;
}


// A rejected constructor cannot have started a request. Retire its actual
// buffers on the same Client. Keep the Library reference through caller/alias
// lifetime: this is not global libcurl or dynamic-module retirement evidence.
static int32_t actql_native_http_retire_failed_client_owned(
  actql_native_http_library *library, actql_native_http_client *client
) {
  if (client == NULL || client->library != library || !client->constructor_failed)
    return -1;
  client->closed = true;
  atomic_store_explicit(&client->cancelled, true, memory_order_relaxed);
  if (client->constructor_metadata_retired) { actql_http_return_child(client); return 0; }
  if (client->test_retire_failures > 0) {
    client->test_retire_failures -= 1;
    return -1;
  }
  actql_http_free(library, client->ca_path);
  actql_http_free(library, client->certificate_path);
  actql_http_free(library, client->key_path);
  actql_http_free(library, client->bearer_path);
  actql_http_free(library, client->response);
  actql_http_free(library, client->error);
  client->ca_path = NULL;
  client->certificate_path = NULL;
  client->key_path = NULL;
  client->bearer_path = NULL;
  client->response = NULL;
  client->response_length = 0;
  client->response_capacity = 0;
  client->error = NULL;
  client->constructor_metadata_retired = true;
  if (client->test_retire_reply_losses > 0) {
    client->test_retire_reply_losses -= 1;
    return -2;
  }
  actql_http_return_child(client);
  return 0;
}


int32_t actql_native_http_retire_failed_client(actql_native_http_library *library, actql_native_http_client *client) {
  if (!client || !library || library->original_process != getpid() ||
      atomic_flag_test_and_set_explicit(&client->lifecycle, memory_order_acquire)) return -1;
  int32_t result = actql_native_http_retire_failed_client_owned(library, client);
  atomic_flag_clear_explicit(&client->lifecycle, memory_order_release);
  return result;
}

// Actual own loader-reference retirement with lost observation, for the
// independent component control only. No later call may reuse that handle.
int32_t actql_native_http_test_lose_ready_library_close(actql_native_http_library *library) {
  if (!library || library->original_process != getpid()) return -1;
  if (actql_http_close_library(library) != 0) return -1;
  actql_http_library_lock(library);
  library->load_close_unknown = true;
  actql_http_library_unlock(library);
  return 0;
}

void actql_native_http_test_fail_constructor_retirement(
  actql_native_http_client *client, int32_t failures, int32_t reply_losses
) {
  if (client != NULL && client->constructor_failed) {
    client->test_retire_failures = failures;
    client->test_retire_reply_losses = reply_losses;
  }
}

int32_t actql_native_http_test_constructor_path_count(actql_native_http_client *client) {
  if (client == NULL) return -1;
  return (client->ca_path != NULL) + (client->certificate_path != NULL) +
    (client->key_path != NULL) + (client->bearer_path != NULL);
}
