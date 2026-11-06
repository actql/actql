/* Test-only ABI module: no network, TLS, resolver, Runtime or stop evidence. */
#include <stdarg.h>
#include <stdlib.h>
#include <stdint.h>
typedef struct { int age; const char *version; unsigned int version_num; const char *host; int features; } info;
typedef struct node { struct node *next; } node;
static int initialized, cleaned;
static void (*callback)(void *);
static void *argument;
// Existing preparation-input diagnostics configure callbacks only in this
// test module, after its real dynamic load and before constructor admission.
static void (*configuration_callback)(int, void *, void *);
static int (*perform_callback)(void *);
static void (*cleanup_callback)(void *);
static void *transport_argument;
int curl_global_init(long flags) { (void)flags; initialized++; return 0; }
void curl_global_cleanup(void) { cleaned++; }
const char *curl_version(void) { return "owned-lifetime-fixture"; }
#ifndef ACTQL_HTTP_OMIT_VERSION_INFO
const info *curl_version_info(int age) {
  (void)age;
#ifdef ACTQL_HTTP_UNKNOWN_VERSION_INFO
  return NULL;
#else
  static const info value = {0, "fixture", 0, "fixture", (1 << 30)
#ifdef ACTQL_HTTP_SSL_CAPABILITY
    | (1 << 2)
#endif
  };
  return &value;
#endif
}
#endif
void *curl_easy_init(void) { return malloc(1); }
int curl_easy_setopt(void *easy, int option, ...) {
  (void)easy;
  if (configuration_callback && option == 10057) {
    va_list args; va_start(args, option); void *client = va_arg(args, void *); va_end(args);
    configuration_callback(option, client, transport_argument);
  }
  return 0;
}
#ifndef ACTQL_HTTP_OMIT_PERFORM
int curl_easy_perform(void *easy) {
  (void)easy;
  if (callback) callback(argument);
  return perform_callback ? perform_callback(transport_argument) : 0;
}
#endif
int curl_easy_getinfo(void *easy, int field, ...) {
  (void)easy; (void)field; va_list args; va_start(args, field); *va_arg(args, long *) = 200; va_end(args); return 0;
}
void curl_easy_cleanup(void *easy) {
  free(easy);
  if (cleanup_callback) cleanup_callback(transport_argument);
}
const char *curl_easy_strerror(int code) { (void)code; return "fixture error"; }
node *curl_slist_append(node *head, const char *line) {
  (void)line; node *item = calloc(1, sizeof(*item)); if (!item) return NULL;
  item->next = head; return item;
}
void curl_slist_free_all(node *head) { while (head) { node *next = head->next; free(head); head = next; } }
int fixture_initialized(void) { return initialized; }
int fixture_cleaned(void) { return cleaned; }
void fixture_callback(void (*value)(void *), void *data) { callback = value; argument = data; }
void fixture_transport_callbacks(
  void (*configure)(int, void *, void *), int (*perform)(void *),
  void (*cleanup)(void *), void *data
) {
  configuration_callback = configure;
  perform_callback = perform;
  cleanup_callback = cleanup;
  transport_argument = data;
}
