/* Existing Signature Owner's original component receiver. It retains the
 * module independently of each Library borrow and never loads a replacement. */
#include <pthread.h>
#include <unistd.h>
#include "../filesystem/observed_component_member.h"

typedef int (*actql_component_bind_fn)(size_t, int *);
typedef int (*actql_component_unit_fn)(void);
typedef void *(*actql_component_symbol_fn)(const char *);
struct actql_original_crypto_component {
  void *module;
  void *context;
  actql_native_command_platform_load *command_load;
  actql_native_observed_component_member *command_member;
  pthread_t thread;
  pid_t process;
  int32_t diagnostic_ceiling;
  uint32_t libraries;
  bool binding_owned, ready, closing, closed, close_unconfirmed;
  actql_component_bind_fn bind;
  actql_component_unit_fn current, enter, leave, borrow, release, close;
  actql_component_symbol_fn symbol;
};
static bool actql_crypto_original_thread(actql_original_crypto_component *value) {
  return value && value->process == getpid() && pthread_equal(value->thread, pthread_self());
}
static bool actql_crypto_original_current(actql_original_crypto_component *value) {
  if (!actql_crypto_original_thread(value)) return false;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return value->context && actql_bootstrap_current_read_context() == value->context &&
    value->ready && !value->closing && value->current && value->current() == 1;
#else
  return false;
#endif
}
/* Normal use has the additional command bootstrap/member fence. Cleanup
 * retains the original component/context predicate above, including when the
 * Runtime has already closed its observed Roots; it cannot load or sign. */
static bool actql_crypto_original_operational_current(actql_original_crypto_component *value) {
  if (!actql_crypto_original_current(value)) return false;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return !value->command_load || actql_native_command_platform_load_current(value->command_load);
#else
  return false;
#endif
}
static bool actql_crypto_original_enter(actql_original_crypto_component *value) {
  return actql_crypto_original_current(value) && value->enter() == 0;
}
static void actql_crypto_original_leave(actql_original_crypto_component *value) {
  if (actql_crypto_original_thread(value) && value->leave) (void)value->leave();
}
static int actql_crypto_original_release_library(actql_original_crypto_component *value) {
  if (!actql_crypto_original_current(value) || !value->libraries) return -1;
  int result = value->release();
  if (result == 0) value->libraries--;
  return result;
}
static void *actql_crypto_original_symbol(actql_original_crypto_component *value, const char *name) {
  if (!actql_crypto_original_operational_current(value)) return NULL;
  void *symbol = value->symbol(name);
  if (symbol && value->command_load) {
    Dl_info original, observed;
    if (!dladdr((void *)value->symbol, &original) ||
        !dladdr(symbol, &observed) || observed.dli_fbase != original.dli_fbase)
      return NULL;
  }
  return symbol;
}
static void actql_crypto_original_finalize(void *raw) {
  (void)raw;
  /* Loss/GC is not an explicit stop/extent/context/module ACK. The trusted
   * installed owner retains this same receiver through partial cleanup. */
}
MOONBIT_FFI_EXPORT
bool actql_native_crypto_component_scope_available(void) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return actql_bootstrap_current_read_context() != NULL;
#else
  return false;
#endif
}
static void *actql_native_crypto_component_load_original(
    moonbit_bytes_t path, int32_t length, int64_t heap_bytes, int32_t ceiling,
    actql_native_observed_component_member *member) {
  actql_original_crypto_component *value = moonbit_make_external_object(
    actql_crypto_original_finalize, sizeof(*value));
  memset(value, 0, sizeof(*value));
  value->thread = pthread_self(); value->process = getpid(); value->diagnostic_ceiling = ceiling;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  value->context = actql_bootstrap_current_read_context();
  if (!value->context || length <= 0 || length > 4096 || ceiling <= 0 ||
      heap_bytes <= 0 || (uint64_t)heap_bytes > SIZE_MAX || memchr(path, 0, length)) return value;
  char name[4097]; memcpy(name, path, length); name[length] = 0;
  if (member) {
    const char *expected = actql_native_observed_component_member_path(member);
    if (!expected || strcmp(expected, name)) return value;
    value->command_member = member; moonbit_incref(member);
    value->command_load = actql_native_command_platform_begin_load(
      actql_native_command_platform_current(), ACTQL_NATIVE_COMMAND_CRYPTO_COMPONENT, member);
    if (!value->command_load) return value;
  }
  value->module = dlopen(name, RTLD_NOW | RTLD_LOCAL);
  if (value->command_load &&
      !actql_native_command_platform_observe_load(value->command_load, value->module))
    return value;
  if (!value->module) return value;
#define COMPONENT(field, spelling) do { \
    dlerror(); *(void **)(&value->field) = dlsym(value->module, spelling); \
    if (dlerror() != NULL || !value->field) return value; \
  } while (0)
  COMPONENT(bind, "actql_crypto_component_bind_current_with_custody");
  COMPONENT(current, "actql_crypto_component_is_current");
  COMPONENT(enter, "actql_crypto_component_enter_current");
  COMPONENT(leave, "actql_crypto_component_leave_current");
  COMPONENT(borrow, "actql_crypto_component_borrow_library");
  COMPONENT(release, "actql_crypto_component_release_library");
  COMPONENT(close, "actql_crypto_component_close");
  COMPONENT(symbol, "actql_crypto_component_symbol");
#undef COMPONENT
  if (member) {
    Dl_info origin, symbol_origin;
    if (!dladdr((void *)value->bind, &origin) ||
        !actql_native_observed_component_member_image(member, origin.dli_fname) ||
        !actql_native_command_platform_load_current(value->command_load)) return value;
    const void *entries[] = {(void *)value->current, (void *)value->enter,
      (void *)value->leave, (void *)value->borrow, (void *)value->release,
      (void *)value->close, (void *)value->symbol};
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++)
      if (!dladdr(entries[i], &symbol_origin) ||
          symbol_origin.dli_fbase != origin.dli_fbase) return value;
  }
  int acquired = 0;
  int result = value->bind((size_t)heap_bytes, &acquired);
  value->binding_owned = acquired == 1;
  value->ready = value->binding_owned && result == 0;
#else
  (void)path; (void)length; (void)heap_bytes; (void)member;
#endif
  return value;
}
MOONBIT_FFI_EXPORT
void *actql_native_crypto_component_load(moonbit_bytes_t path, int32_t length,
                                         int64_t heap_bytes, int32_t ceiling) {
  return actql_native_crypto_component_load_original(path, length, heap_bytes, ceiling, NULL);
}
MOONBIT_FFI_EXPORT
void *actql_native_crypto_component_load_command(moonbit_bytes_t path, int32_t length,
    int64_t heap_bytes, int32_t ceiling, actql_native_observed_component_member *member) {
  /* A missing command member cannot select the legacy diagnostic entrance. */
  if (!member) return NULL;
  return actql_native_crypto_component_load_original(path, length, heap_bytes, ceiling, member);
}
MOONBIT_FFI_EXPORT
bool actql_native_crypto_component_ready(actql_original_crypto_component *value) {
  return actql_crypto_original_operational_current(value);
}
/* Original association only, including a partial or already closed Library.
 * It neither enters a scope nor turns currentness/cleanup into an ACK. The
 * enclosing typed caller still requires its same Host/Read and actual phase. */
MOONBIT_FFI_EXPORT
bool actql_native_crypto_component_owns_library(
    actql_original_crypto_component *value, actql_native_signature_library *library) {
  return actql_crypto_original_thread(value) && library && library->component == value;
}
MOONBIT_FFI_EXPORT
int32_t actql_native_crypto_component_close(actql_original_crypto_component *value) {
  if (!actql_crypto_original_thread(value)) return 2;
  if (value->closed) return 0;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (actql_bootstrap_current_read_context() != value->context) return 2;
#else
  return 2;
#endif
  if (value->libraries) return 1;
  value->closing = true;
  if (value->close_unconfirmed) return 3;
  if (value->binding_owned && value->close() != 0) return 1;
  /* Component ACK is not dlclose ACK. A failed dlclose stays sticky and is
   * never retried or repaired through another module load. */
  void *module = value->module;
  if (module && dlclose(module) != 0) {
    value->close_unconfirmed = true; return 3;
  }
  value->module = NULL;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  if (value->command_load &&
      !actql_native_command_platform_module_released(value->command_load, module)) {
    value->close_unconfirmed = true; return 3;
  }
#endif
  if (value->command_member) {
    moonbit_decref(value->command_member); value->command_member = NULL;
  }
  value->ready = false; value->closed = true;
  return 0;
}
MOONBIT_FFI_EXPORT
void *actql_native_crypto_component_library(actql_original_crypto_component *value) {
  actql_native_signature_library *library = moonbit_make_external_object(
    actql_native_signature_library_finalize, sizeof(*library));
  memset(library, 0, sizeof(*library));
  library->original_allocator = true;
  library->component = value; moonbit_incref(value);
  library->diagnostic_ceiling = value->diagnostic_ceiling;
  if (!actql_crypto_original_operational_current(value) || value->libraries == UINT32_MAX) return library;
  ACTQL_SIGNATURE_SCOPE(library, library);
  if (value->borrow() != 0) return library;
  value->libraries++; library->component_borrowed = true; library->dynamic_library = value->module;
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
      !ACTQL_LOAD(library, err_error_string_n, "ERR_error_string_n")) library->closing = true;
  return library;
}
