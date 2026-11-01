#include "component_tls_lifetime.h"

#include <openssl/crypto.h>
#include <openssl/ssl.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

#if !defined(OPENSSL_NO_PINSHARED) || !defined(OPENSSL_NO_ATEXIT)
#error This private component requires explicit unloadable OpenSSL construction
#endif

// These are references to this image's private static TLS dependency. They
// grant no execution or budget. Every admitted Library balances exactly one
// reference after all of its actual easy/Client cleanup has returned.
static atomic_flag lifecycle = ATOMIC_FLAG_INIT;
static size_t references;
static bool stopped;
static bool initialization_failed;
static _Atomic(pid_t) original_process;
static actql_http_component_memory memory;
static _Atomic(size_t) live_allocations;

static bool current_process(void) {
  pid_t process = getpid(), expected = 0;
  atomic_compare_exchange_strong_explicit(&original_process, &expected, process,
    memory_order_acq_rel, memory_order_acquire);
  return atomic_load_explicit(&original_process, memory_order_acquire) == process;
}

static void lock(void) {
  while (atomic_flag_test_and_set_explicit(&lifecycle, memory_order_acquire)) {}
}

static void unlock(void) {
  atomic_flag_clear_explicit(&lifecycle, memory_order_release);
}

static void *allocate(size_t bytes) {
  if (!current_process() || !memory.allocate) return NULL;
  void *pointer = memory.allocate(memory.read, memory.lease, bytes);
  if (pointer) atomic_fetch_add_explicit(&live_allocations, 1, memory_order_relaxed);
  return pointer;
}

static void retire(void *pointer) {
  if (!pointer) return;
  if (!current_process() || !memory.retire) abort();
  memory.retire(memory.read, memory.lease, pointer);
  if (atomic_fetch_sub_explicit(&live_allocations, 1, memory_order_acq_rel) == 0) abort();
}

static void *reallocate(void *pointer, size_t bytes) {
  if (!pointer) return allocate(bytes);
  if (!bytes) { retire(pointer); return NULL; }
  if (!current_process() || !memory.reallocate) return NULL;
  // The provider preserves the original during the full replacement. A
  // refusal leaves both the original bytes and this live count unchanged.
  return memory.reallocate(memory.read, memory.lease, pointer, bytes);
}

static char *duplicate(const char *text) {
  size_t bytes = strlen(text);
  if (bytes == SIZE_MAX) return NULL;
  char *copy = allocate(bytes + 1);
  if (copy) memcpy(copy, text, bytes + 1);
  return copy;
}

static void *allocate_zeroed(size_t count, size_t bytes) {
  if (bytes && count > SIZE_MAX / bytes) return NULL;
  size_t total = count * bytes;
  void *pointer = allocate(total);
  if (pointer) memset(pointer, 0, total);
  return pointer;
}

static void *tls_allocate(size_t bytes, const char *file, int line) {
  (void)file; (void)line;
  return allocate(bytes);
}
static void *tls_reallocate(void *pointer, size_t bytes, const char *file, int line) {
  (void)file; (void)line;
  return reallocate(pointer, bytes);
}
static void tls_retire(void *pointer, const char *file, int line) {
  (void)file; (void)line;
  retire(pointer);
}

static int acquire(const actql_http_component_memory *original) {
  // Refuse an inherited image before touching a possibly inherited lock.
  if (!current_process() || !original || !original->allocate ||
      !original->reallocate || !original->retire) return -1;
  lock();
  if (stopped || initialization_failed || references == SIZE_MAX) { unlock(); return -1; }
  if (references == 0) {
    memory = *original;
    // Install before the first TLS allocation. The checked initializer below
    // supplies NO_LOAD_CONFIG; this image was also built without atexit.
    if (CRYPTO_set_mem_functions(tls_allocate, tls_reallocate, tls_retire) != 1) {
      memset(&memory, 0, sizeof(memory));
      stopped = true;
      unlock();
      return -1;
    }
    // Publish the original acquired reference BEFORE fallible TLS work. Curl's
    // selected backend does not propagate OPENSSL_init_ssl failure itself.
    references = 1;
    uint64_t flags = OPENSSL_INIT_NO_ATEXIT | OPENSSL_INIT_NO_LOAD_CONFIG;
#ifdef OPENSSL_INIT_ENGINE_ALL_BUILTIN
    flags |= OPENSSL_INIT_ENGINE_ALL_BUILTIN;
#endif
    if (OPENSSL_init_ssl(flags, NULL) != 1) {
      initialization_failed = true;
      unlock();
      return 1;
    }
    unlock();
    return 0;
  } else if (memory.read != original->read || memory.lease != original->lease ||
             memory.allocate != original->allocate ||
             memory.reallocate != original->reallocate || memory.retire != original->retire) {
    unlock();
    return -1;
  }
  references++;
  unlock();
  return 0;
}

static void cleanup_thread(void) {
  if (current_process()) OPENSSL_thread_stop();
}

static int release(void) {
  if (!current_process()) return -1;
  lock();
  if (references == 0) { unlock(); return -1; }
  if (references > 1) {
    OPENSSL_thread_stop();
    references--;
  } else {
    // No other admitted Library, request thread or private resolver worker
    // remains. This image cannot be reinitialized after OPENSSL_cleanup; a
    // fresh load must really unload/reload it, rather than reset private flags.
    if (!stopped) {
      OPENSSL_thread_stop();
      OPENSSL_cleanup();
      stopped = true;
    }
    // Keep the last Library/Read and image while any actual curl/TLS alias
    // remains. Provider retirement debt remains with that same Read as well.
    if (atomic_load_explicit(&live_allocations, memory_order_acquire) != 0) {
      unlock();
      return -1;
    }
    references = 0;
  }
  unlock();
  return 0;
}

// curl's selected export rule keeps curl_* symbols. This deliberately named
// private extension exposes only same-image cleanup functions, never a TLS
// object or an execution/permission handle to the caller.
__attribute__((visibility("default")))
const actql_http_component_tls_api *curl_actql_native_tls_api_v3(void) {
  static const actql_http_component_tls_api api = {
    3, sizeof(actql_http_component_tls_api), acquire, cleanup_thread, release,
    allocate, retire, reallocate, duplicate, allocate_zeroed
  };
  return &api;
}
