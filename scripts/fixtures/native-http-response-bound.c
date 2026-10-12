// Matching diagnostic of the real HTTP Owner's configured limit projection.
// It does not enter libcurl or authorize transport, grants or Store custody.
#include "../../src/platform_native/http_client/http_client_stub.c"
#include <assert.h>
#include <stdio.h>

_Noreturn void moonbit_panic(void) { abort(); }

static int cases;
static void check_bound(int64_t configured, int64_t expected) {
  actql_native_http_library library = {0};
  actql_native_http_client client = {.library = &library, .max_response_bytes = configured};
  atomic_init(&client.cancelled, false);
  assert(actql_native_http_client_response_limit(&client) == expected);
  assert(!client.closed && !atomic_load(&client.cancelled));
  assert(client.response == NULL && client.response_length == 0);
  cases += 1;
}

int main(void) {
  check_bound(0, 0);
  check_bound(1, 1);
  check_bound(65536, 65536);
  check_bound(INT32_MAX, INT32_MAX);
  check_bound(-1, -2);
  check_bound((int64_t)INT32_MAX + 1, -2);
  assert(actql_native_http_client_response_limit(NULL) == -2);
  cases += 1;
  actql_native_http_library library = {0};
  actql_native_http_client client = {.library = &library, .max_response_bytes = 65536, .closed = true};
  atomic_init(&client.cancelled, false);
  assert(actql_native_http_client_response_limit(&client) == -1);
  cases += 1;
  client.closed = false;
  atomic_store(&client.cancelled, true);
  assert(actql_native_http_client_response_limit(&client) == -3);
  cases += 1;
  atomic_store(&client.cancelled, false);
  client.library = NULL;
  assert(actql_native_http_client_response_limit(&client) == -2);
  cases += 1;
  printf("{\"cases\":%d,\"physical_entries\":0,\"public_acceptance\":false}\n", cases);
}
