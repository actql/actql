// Matching C diagnostic: real filesystem/HTTP stubs and MoonBit runtime,
// deterministic transport boundary only. No Provider or public Host is used.
#include "../../src/platform_native/http_client/http_client_stub.c"
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>

// Generated MoonBit programs supply this panic exit; the C diagnostic aborts
// on the same runtime failure instead of supplying a substitute allocator.
_Noreturn void moonbit_panic(void) { abort(); }

extern void *actql_native_filesystem_open_private_root(moonbit_bytes_t, int32_t);
extern void *actql_native_filesystem_adopt_private_file_projection(
  void *, moonbit_bytes_t, int32_t
);
extern int32_t actql_native_filesystem_private_file_projection_ready(void *);

struct curl_slist { char *text; struct curl_slist *next; };
static int sends, cleanups, scenarios;
static bool lose_response, replace_during_configuration, cancel_during_configuration;
static char original_path[4096], replacement_path[4096];

static moonbit_bytes_t bytes(const char *text) {
  size_t length = strlen(text);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)length);
  memcpy(result, text, length);
  return result;
}

static void write_secret(const char *path, const char *text) {
  int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  assert(descriptor >= 0);
  assert(write(descriptor, text, strlen(text)) == (ssize_t)strlen(text));
  assert(close(descriptor) == 0);
}

static actql_native_private_file_projection *adopt(void *root, const char *name) {
  moonbit_bytes_t encoded = bytes(name);
  void *result = actql_native_filesystem_adopt_private_file_projection(
    root, encoded, (int32_t)strlen(name)
  );
  moonbit_decref(encoded);
  assert(actql_native_filesystem_private_file_projection_ready(result));
  return result;
}

static bool read_original(actql_native_private_file_projection *original) {
  char *authorization = NULL;
  size_t length = 0;
  bool accepted = actql_read_bearer_authorization(
    NULL, original, 8192, true, &authorization, &length
  );
  if (accepted) assert(strcmp(authorization, "Authorization: Bearer fixture-token") == 0);
  actql_forget_authorization(authorization, length);
  return accepted;
}

// A replaced FIFO must be refused before opening can block. Isolate the probe
// so the diagnostic can reap a defective implementation instead of hanging.
static void assert_fifo_refused(actql_native_private_file_projection *original) {
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) _exit(read_original(original) ? 1 : 0);
  int status = 0;
  struct timespec interval = {0, 10000000};
  for (int tick = 0; tick < 100; tick += 1) {
    pid_t observed = waitpid(child, &status, WNOHANG);
    assert(observed >= 0);
    if (observed == child) {
      assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
      return;
    }
    assert(nanosleep(&interval, NULL) == 0);
  }
  assert(kill(child, SIGKILL) == 0);
  assert(waitpid(child, &status, 0) == child && WIFSIGNALED(status));
  fprintf(stderr, "original installation read blocked on a replacement FIFO\n");
  assert(false);
}

static void passed(const char *name) {
  scenarios += 1;
  printf("ok %d - %s\n", scenarios, name);
}

static CURL *fixture_init(void) { return (CURL *)1; }
static CURLcode fixture_setopt(CURL *curl, CURLoption option, ...) {
  (void)curl;
  if (option == ACTQL_CURLOPT_XFERINFODATA && replace_during_configuration) {
    assert(rename(original_path, replacement_path) == 0);
    write_secret(original_path, "fixture-token\n");
    replace_during_configuration = false;
  }
  if (option == ACTQL_CURLOPT_XFERINFODATA && cancel_during_configuration) {
    va_list args; va_start(args, option);
    actql_native_http_client *client = va_arg(args, actql_native_http_client *);
    va_end(args);
    assert(actql_native_http_client_cancel(client));
    cancel_during_configuration = false;
  }
  return ACTQL_CURLE_OK;
}
static CURLcode fixture_perform(CURL *curl) {
  (void)curl; sends += 1;
  return lose_response ? ACTQL_CURLE_WRITE_ERROR : ACTQL_CURLE_OK;
}
static CURLcode fixture_getinfo(CURL *curl, CURLINFO info, ...) {
  (void)curl; (void)info;
  va_list args; va_start(args, info);
  *va_arg(args, long *) = 204;
  va_end(args);
  return ACTQL_CURLE_OK;
}
static void fixture_cleanup(CURL *curl) { (void)curl; cleanups += 1; }
static const char *fixture_error(CURLcode code) { (void)code; return "fixture response lost"; }
static curl_slist *fixture_append(curl_slist *list, const char *text) {
  curl_slist *entry = calloc(1, sizeof(*entry)); assert(entry != NULL);
  entry->text = strdup(text); assert(entry->text != NULL);
  if (list == NULL) return entry;
  curl_slist *tail = list; while (tail->next != NULL) tail = tail->next;
  tail->next = entry; return list;
}
static void fixture_free(curl_slist *list) {
  while (list != NULL) {
    curl_slist *next = list->next; free(list->text); free(list); list = next;
  }
}

static int request_with_deadline(
  actql_native_private_file_projection *original, bool unknown, int64_t expires_at
) {
  actql_native_http_library library = {
    .easy_init = fixture_init, .easy_setopt = fixture_setopt,
    .easy_perform = fixture_perform, .easy_getinfo = fixture_getinfo,
    .easy_cleanup = fixture_cleanup, .easy_strerror = fixture_error,
    .slist_append = fixture_append, .slist_free_all = fixture_free,
  };
  actql_native_http_client client = { .library = &library, .max_response_bytes = 64 };
  atomic_init(&client.cancelled, false);
  moonbit_bytes_t method = bytes("GET"), url = bytes("https://example.invalid/observe");
  moonbit_bytes_t headers = bytes("accept: application/json\n"), body = bytes("");
  lose_response = unknown;
  int result = actql_native_http_client_get_local_preparation(
    &client, method, 3, url, 31, headers, 25, body, 0, original,
    expires_at
  );
  moonbit_decref(method); moonbit_decref(url);
  moonbit_decref(headers); moonbit_decref(body);
  free(client.error); free(client.response);
  return result;
}

static int request(actql_native_private_file_projection *original, bool unknown) {
  return request_with_deadline(original, unknown, INT64_C(2000000000000));
}

int main(int argc, char **argv) {
  assert(argc == 2);
  const char *root_path = argv[1];
  moonbit_bytes_t path = bytes(root_path);
  void *root = actql_native_filesystem_open_private_root(path, (int32_t)strlen(root_path));
  moonbit_decref(path);
  snprintf(original_path, sizeof(original_path), "%s/bearer", root_path);
  snprintf(replacement_path, sizeof(replacement_path), "%s/retired", root_path);
  write_secret(original_path, "fixture-token\n");
  actql_native_private_file_projection *original = adopt(root, "bearer");
  assert(read_original(original));
  assert(request_with_deadline(original, false, 1) == 4 && sends == 0);
  assert(request(original, false) == 0 && sends == 1 && cleanups == 1);
  passed("original private installation reaches the bounded GET hook");

  assert(rename(original_path, replacement_path) == 0);
  write_secret(original_path, "fixture-token\n");
  char *authorization = NULL; size_t length = 0;
  // Actual old rotation branch accepts the replacement, even with equal bytes.
  assert(actql_read_bearer_authorization(
    original_path, NULL, 8192, false, &authorization, &length
  ));
  actql_forget_authorization(authorization, length);
  assert(!read_original(original));
  assert(request(original, false) == 5 && sends == 1);
  passed("same-byte replacement keeps ordinary rotation but refuses original preparation");
  moonbit_decref(original);

  original = adopt(root, "bearer");
  assert(unlink(replacement_path) == 0 && rename(original_path, replacement_path) == 0);
  assert(!read_original(original));
  passed("renamed original is not followed to a new name");
  assert(symlink(replacement_path, original_path) == 0);
  assert(!read_original(original));
  passed("symlink replacement never provides the original opened file");
  assert(unlink(original_path) == 0);
  moonbit_decref(original);

  write_secret(original_path, "fixture-token\n");
  original = adopt(root, "bearer");
  write_secret(original_path, "changed-token\n");
  struct timespec changed[2] = {{1, 0}, {2, 0}};
  assert(utimensat(AT_FDCWD, original_path, changed, 0) == 0);
  assert(!read_original(original));
  passed("same-inode same-size mutation does not match the original generation");
  moonbit_decref(original);

  write_secret(original_path, "fixture-token\n");
  original = adopt(root, "bearer");
  assert(chmod(original_path, 0640) == 0 && !read_original(original));
  assert(chmod(original_path, 0600) == 0);
  passed("permission revocation refuses the installation");
  moonbit_decref(original);

  original = adopt(root, "bearer");
  assert(unlink(replacement_path) == 0 && link(original_path, replacement_path) == 0);
  assert(!read_original(original));
  passed("additional file alias is refused");
  assert(unlink(replacement_path) == 0);
  moonbit_decref(original);

  original = adopt(root, "bearer");
  replace_during_configuration = true;
  assert(request(original, false) == 5 && sends == 1 && cleanups == 2);
  passed("replacement after header preparation is refused at transport entry");
  moonbit_decref(original);

  original = adopt(root, "bearer");
  assert(request(original, true) == -1 && sends == 2 && cleanups == 3);
  passed("response loss remains transport failure with physical cleanup");
  cancel_during_configuration = true;
  assert(request(original, false) == 2 && sends == 2 && cleanups == 4);
  passed("cancellation during configuration prevents transport entry");
  moonbit_decref(original);

  write_secret(original_path, "");
  moonbit_bytes_t name = bytes("bearer");
  void *empty = actql_native_filesystem_adopt_private_file_projection(root, name, 6);
  assert(!actql_native_filesystem_private_file_projection_ready(empty));
  moonbit_decref(empty); moonbit_decref(name);
  passed("empty installation is refused before transport");

  write_secret(original_path, "fixture-token\n");
  original = adopt(root, "bearer");
  assert(unlink(original_path) == 0 && mkfifo(original_path, 0600) == 0);
  assert_fifo_refused(original);
  assert(unlink(original_path) == 0);
  moonbit_decref(original);
  passed("FIFO replacement is refused without blocking or transport entry");

  write_secret(original_path, "fixture-token\n");
  original = adopt(root, "bearer");
  assert(chmod(root_path, 0750) == 0 && !read_original(original));
  assert(chmod(root_path, 0700) == 0);
  passed("private-root revocation is checked again");

  char moved[4096]; snprintf(moved, sizeof(moved), "%s-moved", root_path);
  assert(rename(root_path, moved) == 0 && mkdir(root_path, 0700) == 0);
  assert(!read_original(original));
  assert(rmdir(root_path) == 0 && rename(moved, root_path) == 0);
  passed("directory replacement refuses retained fd with lost namespace custody");
  moonbit_decref(original); moonbit_decref(root);
  assert(scenarios == 14 && sends == 2 && cleanups == 4);
  printf("{\"cases\":14,\"transport_entries\":2,\"transport_cleanups\":4,\"public_acceptance\":false}\n");
  return 0;
}
