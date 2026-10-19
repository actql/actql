/* Actual selected-provider filesystem observation cases. These observations
 * cannot issue the command bootstrap, load permission or a normal profile. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/wait.h>
#include "owned_capacity.h"
#include "scoped_read.h"
#include "../filesystem_stub.c"

#ifdef ACTQL_COMMAND_LOAD_CASE
/* Renamed only while compiling the two component adapters for the unavailable
 * entry counter. Any loader call is a failure, never a fallback supplier. */
static unsigned refused_loader_calls;
void *actql_test_unavailable_dlopen(const char *path, int mode) {
  (void)path; (void)mode; refused_loader_calls++; return NULL;
}
extern void *actql_native_sqlite_load_command_component(
  moonbit_bytes_t, int32_t, int32_t, int64_t, actql_native_observed_component_member *);
extern int32_t actql_native_sqlite_library_ready(void *);
extern int32_t actql_native_sqlite_library_close_checked(void *);
extern void *actql_native_crypto_component_load_command(
  moonbit_bytes_t, int32_t, int64_t, int32_t, actql_native_observed_component_member *);
extern bool actql_native_crypto_component_ready(void *);
extern int32_t actql_native_crypto_component_close(void *);

#endif

static const unsigned char recipe[32] = {17};
static moonbit_bytes_t bytes(const char *text) {
  size_t length = strlen(text);
  moonbit_bytes_t value = moonbit_make_bytes_raw((int32_t)length);
  memcpy(value, text, length);
  return value;
}
static void *foreign_thread(void *raw) {
  assert(!actql_native_observed_component_member_current(raw));
  assert(!actql_native_observed_component_member_runtime(raw));
  return NULL;
}
int main(int argc, char **argv) {
  assert(argc == 3);
  const char *name = argv[1], *directory = argv[2];
  assert(mkdir(directory, 0700) == 0);
  char path[4097];
  assert(snprintf(path, sizeof(path), "%s/component.bin", directory) > 0);
  int fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0600);
  assert(fd >= 0 && write(fd, "original", 8) == 8 && close(fd) == 0);
  actql_owned_capacity *lease = NULL;
  actql_read_context *context = NULL;
  assert(actql_native_owned_acquire(64 * (size_t)sysconf(_SC_PAGESIZE),
    1, recipe, &lease) == 0);
  assert(actql_native_owned_transfer(lease, 1, recipe) == 0);
  assert(actql_native_owned_enter(lease) == 0);
  assert(actql_read_context_create(lease, &context) == 0);
  assert(actql_read_context_retain(context) == 0);
  assert(actql_read_context_enter(context) == 0);
  actql_native_filesystem_root *root = NULL;
  assert(actql_native_filesystem_scoped_open_root(context,
    (moonbit_bytes_t)directory, (int32_t)strlen(directory), 128, &root) == 0);
  assert(root && root->fd >= 0);
  moonbit_bytes_t object = bytes("component.bin");
  moonbit_bytes_t source = bytes("1111111111111111111111111111111111111111");
  moonbit_bytes_t manifest = bytes("2222222222222222222222222222222222222222222222222222222222222222");
  moonbit_bytes_t digest = bytes("3333333333333333333333333333333333333333333333333333333333333333");
  actql_native_observed_file_stat *stat = actql_native_filesystem_observe_file(
    root, object, Moonbit_array_length(object));
  assert(stat && stat->issue_kind == 0);
  actql_native_observed_component_member *member =
    actql_native_filesystem_observed_component_member(root, stat, object,
      Moonbit_array_length(object), 1, source, manifest, digest);
  /* A fixture-local nominal association tests one-shot attachment only. It is
   * not a Runtime, initial original, loader permission or hash validation. */
  int association, other;
  assert(actql_native_filesystem_bind_component_runtime(member, &association));
  assert(!actql_native_filesystem_bind_component_runtime(member, &other));
  assert(actql_native_observed_component_member_current(member));
  assert(actql_native_observed_component_member_runtime(member) == &association);
  assert(actql_native_observed_component_member_kind(member) == 1);
  assert(!strcmp(actql_native_observed_component_member_path(member), path));
  assert(!memcmp(actql_native_observed_component_member_source(member), source, 40));
  assert(actql_native_observed_component_member_image(member, path));
#ifdef ACTQL_COMMAND_LOAD_CASE
  if (!strcmp(name, "command-unavailable")) {
    /* The real entry implementation has no admitted initial original in this
     * fixture. Positive file DATA and actual Read backing cannot create one. */
    assert(actql_native_command_platform_current() == NULL);
    void *sqlite = actql_native_sqlite_load_command_component(
      (moonbit_bytes_t)path, (int32_t)strlen(path), 128,
      32 * (int64_t)sysconf(_SC_PAGESIZE), member);
    assert(sqlite && !actql_native_sqlite_library_ready(sqlite));
    assert(actql_native_sqlite_library_close_checked(sqlite));
    moonbit_decref(sqlite);
    actql_native_observed_component_member *crypto_member =
      actql_native_filesystem_observed_component_member(root, stat, object,
        Moonbit_array_length(object), 2, source, manifest, digest);
    assert(actql_native_filesystem_bind_component_runtime(crypto_member, &association));
    void *crypto = actql_native_crypto_component_load_command(
      (moonbit_bytes_t)path, (int32_t)strlen(path),
      32 * (int64_t)sysconf(_SC_PAGESIZE), 128, crypto_member);
    assert(crypto && !actql_native_crypto_component_ready(crypto));
    assert(actql_native_crypto_component_close(crypto) == 0);
    moonbit_decref(crypto); moonbit_decref(crypto_member);
    assert(refused_loader_calls == 0);
  } else
#endif
  if (!strcmp(name, "foreign-thread")) {
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_thread, member) == 0);
    assert(pthread_join(thread, NULL) == 0);
    assert(actql_native_observed_component_member_current(member));
  } else if (!strcmp(name, "foreign-process")) {
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
      assert(!actql_native_observed_component_member_current(member));
      _exit(0); /* No parent or member cleanup ACK is inferred. */
    }
    int status; assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(actql_native_observed_component_member_current(member));
  } else if (!strcmp(name, "mutation")) {
    assert(chmod(path, 0640) == 0);
    assert(!actql_native_observed_component_member_current(member));
    assert(!actql_native_observed_component_member_image(member, path));
    assert(!actql_native_observed_component_member_path(member));
  } else {
    assert(!strcmp(name, "identity"));
  }
  int32_t physical = -1;
  assert(actql_native_filesystem_scoped_root_close(root, &physical) == 0);
  assert(physical == 0 && !root->read_context_user);
  assert(!actql_native_observed_component_member_current(member));
  assert(!actql_native_observed_component_member_runtime(member));
  moonbit_decref(member); moonbit_decref(stat); moonbit_decref(root);
  moonbit_decref(object); moonbit_decref(source);
  moonbit_decref(manifest); moonbit_decref(digest);
  assert(actql_read_context_leave(context) == 0);
  assert(actql_native_owned_leave(lease) == 0);
  assert(actql_read_context_release_after_owner_ack(context) == 0);
  assert(actql_read_context_try_close(&context) == 0);
  assert(actql_native_owned_try_close(&lease) == 0);
  printf("{\"case\":\"%s\",\"passed\":true,\"originalsClosed\":true,"
    "\"commandBootstrap\":false,\"installed\":false}\n", name);
  return 0;
}
