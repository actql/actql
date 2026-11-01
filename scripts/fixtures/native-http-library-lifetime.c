/* Actual existing Owner + loader reference tests. The dynamic test module
 * performs no HTTP/TLS/resolver work; no case is whole Host stop evidence. */
#include "../../src/platform_native/http_client/http_client_stub.c"
#include <assert.h>
#include <stdio.h>
#include <sys/wait.h>
#include <pthread.h>
_Noreturn void moonbit_panic(void) { abort(); }
static moonbit_bytes_t bytes(const char *text) {
  size_t n = strlen(text); moonbit_bytes_t b = moonbit_make_bytes_raw((int32_t)n); memcpy(b, text, n); return b;
}
static actql_native_http_client *child(actql_native_http_library *library) {
  moonbit_bytes_t ca = bytes("/unused/ca"), cert = bytes("/unused/cert"), key = bytes("/unused/key");
  actql_native_http_client *client = actql_native_http_create_client(library,
    ca, 10, cert, 12, key, 11, 32, 10, 20);
  moonbit_decref(ca); moonbit_decref(cert); moonbit_decref(key); return client;
}
static void during_request(void *data) {
  actql_native_http_client *client = data;
  assert(actql_native_http_library_close_checked(client->library) == -2);
  assert(actql_native_http_client_close_checked(client) != 0);
  assert(client->ca_path != NULL && !client->closed && client->holder_counted);
}
static atomic_int release_waiters;
static atomic_bool release_start;
static void *concurrent_failed_release(void *value) {
  atomic_fetch_add(&release_waiters, 1);
  while (!atomic_load(&release_start)) {}
  return (void *)(intptr_t)actql_native_http_retire_failed_library(value);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  void *observer = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL); assert(observer);
  int (*initialized)(void) = dlsym(observer, "fixture_initialized");
  int (*cleaned)(void) = dlsym(observer, "fixture_cleaned");
  void (*callback)(void (*)(void *), void *) = dlsym(observer, "fixture_callback");
  assert(initialized && cleaned && callback);
  moonbit_bytes_t path = bytes(argv[1]);
  actql_native_http_library *library = actql_native_http_load_library_with_custody(path, (int32_t)strlen(argv[1]), 256);
  moonbit_decref(path);
  if (!strcmp(argv[2], "foreign-failed-finalizer")) {
    assert(!actql_native_http_library_ready(library));
    assert(library->load_failed && !library->init_attempted && library->dynamic_library);
    pid_t forked = fork(); assert(forked >= 0);
    if (forked == 0) {
      void *original = library->dynamic_library;
      actql_native_http_library_finalize(library);
      assert(library->dynamic_library == original && !library->load_close_unknown);
      assert(initialized() == 0 && cleaned() == 0);
      _exit(0);
    }
    int status = 0; assert(waitpid(forked, &status, 0) == forked);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(library->dynamic_library && !library->load_close_unknown);
    assert(actql_native_http_retire_failed_library(library) == 0);
    moonbit_decref(library); assert(dlclose(observer) == 0);
    puts("PASS foreign-failed-finalizer; no caller or Runtime ACK");
    return 0;
  }
  if (!strcmp(argv[2], "concurrent-failed-load")) {
    assert(!actql_native_http_library_ready(library));
    assert(library->load_failed && !library->init_attempted && library->dynamic_library);
    atomic_init(&release_waiters, 0); atomic_init(&release_start, false);
    pthread_t first, second;
    assert(pthread_create(&first, NULL, concurrent_failed_release, library) == 0);
    assert(pthread_create(&second, NULL, concurrent_failed_release, library) == 0);
    while (atomic_load(&release_waiters) != 2) {}
    atomic_store(&release_start, true);
    void *a, *b; assert(pthread_join(first, &a) == 0); assert(pthread_join(second, &b) == 0);
    assert((intptr_t)a == 0 && (intptr_t)b == 0);
    assert(library->dynamic_library == NULL && !library->load_close_unknown);
    assert(initialized() == 0 && cleaned() == 0);
    assert(actql_native_http_retire_failed_library(library) == 0);
    moonbit_decref(library); assert(dlclose(observer) == 0);
    puts("PASS concurrent-failed-load; same original release, no init or Runtime ACK");
    return 0;
  }
  assert(actql_native_http_library_ready(library)); assert(initialized() == 1);
  if (!strcmp(argv[2], "ready-child")) {
    actql_native_http_client *client = child(library); assert(actql_native_http_client_ready(client));
    assert(actql_native_http_test_live_children(library) == 1);
    assert(actql_native_http_library_close_checked(library) == -2);
    assert(cleaned() == 0 && !actql_native_http_library_ready(library));
    assert(actql_native_http_client_close_checked(client) == 0);
    assert(actql_native_http_client_close_checked(client) == 0);
    assert(actql_native_http_test_live_children(library) == 0);
    assert(actql_native_http_library_close_checked(library) == 0 && cleaned() == 1);
    assert(actql_native_http_library_close_checked(library) == 0 && cleaned() == 1);
    moonbit_decref(client);
  } else if (!strcmp(argv[2], "failed-child")) {
    actql_native_http_test_fail_constructor_path(library, 2);
    actql_native_http_client *client = child(library); assert(!actql_native_http_client_ready(client));
    assert(client->constructor_failed && actql_native_http_test_live_children(library) == 1);
    assert(actql_native_http_library_close_checked(library) == -2);
    actql_native_http_test_fail_constructor_retirement(client, 1, 1);
    assert(actql_native_http_retire_failed_client(library, client) == -1);
    assert(actql_native_http_test_live_children(library) == 1 && client->ca_path != NULL);
    assert(actql_native_http_retire_failed_client(library, client) == -2);
    assert(actql_native_http_test_live_children(library) == 1 && client->ca_path == NULL);
    assert(actql_native_http_library_close_checked(library) == -2);
    assert(actql_native_http_retire_failed_client(library, client) == 0);
    assert(actql_native_http_retire_failed_client(library, client) == 0);
    assert(actql_native_http_test_live_children(library) == 0);
    assert(actql_native_http_library_close_checked(library) == 0 && cleaned() == 1);
    moonbit_decref(client);
  } else if (!strcmp(argv[2], "inflight")) {
    actql_native_http_client *client = child(library); assert(actql_native_http_client_ready(client));
    callback(during_request, client);
    moonbit_bytes_t url = bytes("https://example.invalid/fixture"), body = bytes("{}");
    assert(actql_native_http_client_post_json(client, url, (int32_t)strlen("https://example.invalid/fixture"), body, 2) == 2);
    moonbit_decref(url); moonbit_decref(body);
    assert(actql_native_http_client_close_checked(client) == 0);
    assert(actql_native_http_test_live_children(library) == 0);
    void *original_module = library->dynamic_library;
    assert(actql_native_http_library_close_checked(library) == -3);
    assert(cleaned() == 1 && !library->init_owned);
    assert(library->dynamic_library == original_module && !library->released);
    assert(!actql_native_http_library_ready(library));
    assert(actql_native_http_library_close_checked(library) == -3 && cleaned() == 1);
    assert(library->dynamic_library == original_module && !library->released);
    moonbit_decref(client);
  } else if (!strcmp(argv[2], "foreign-process")) {
    actql_native_http_client *client = child(library); assert(actql_native_http_client_ready(client));
    pid_t forked = fork(); assert(forked >= 0);
    if (forked == 0) {
      assert(actql_native_http_library_close_checked(library) != 0);
      assert(actql_native_http_client_close_checked(client) != 0);
      assert(!actql_native_http_client_close(client));
      _exit(0);
    }
    int status = 0; assert(waitpid(forked, &status, 0) == forked);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(actql_native_http_test_live_children(library) == 1 && cleaned() == 0);
    assert(actql_native_http_client_close_checked(client) == 0);
    assert(actql_native_http_library_close_checked(library) == 0 && cleaned() == 1);
    moonbit_decref(client);
  } else if (!strcmp(argv[2], "lost-release")) {
    assert(actql_native_http_test_lose_ready_library_close(library) == 0);
    assert(cleaned() == 1 && !actql_native_http_library_ready(library));
    assert(actql_native_http_library_close_checked(library) == -3);
    assert(actql_native_http_library_close_checked(library) == -3 && cleaned() == 1);
  } else abort();
  moonbit_decref(library);
  assert(dlclose(observer) == 0);
  printf("PASS %s; owned references only, no Runtime/physical-stop ACK\n", argv[2]);
}
