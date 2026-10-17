#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

static int calls, fail_call;
static int original_sigaction(int signal_number, const struct sigaction *action,
                              struct sigaction *old) {
  calls += 1;
  if (calls == fail_call) { errno = EIO; return -1; }
  return sigaction(signal_number, action, old);
}
#define sigaction(...) original_sigaction(__VA_ARGS__)
#include "../../src/cmd/native_client/stdout_stub.c"
#undef sigaction

#define REQUIRE(value) do { if (!(value)) return __LINE__; } while (0)
int main(int argc, char **argv) {
  REQUIRE(argc == 2);
  struct sigaction selected = {0}, observed;
  selected.sa_handler = SIG_IGN;
  sigemptyset(&selected.sa_mask);
  REQUIRE(sigaction(SIGINT, &selected, NULL) == 0);
  REQUIRE(sigaction(SIGTERM, &selected, NULL) == 0);
  if (strcmp(argv[1], "partial") == 0) {
    fail_call = 4;
    REQUIRE(!actql_native_client_status_watch_begin());
    REQUIRE(actql_status_watching && calls == 4);
    REQUIRE(!actql_native_client_status_watch_begin() && calls == 4);
    REQUIRE(actql_native_client_status_watch_end());
    REQUIRE(!actql_status_watching && calls == 6);
  } else {
    REQUIRE(actql_native_client_status_watch_begin());
    REQUIRE(calls == 4);
    if (strcmp(argv[1], "restore") == 0) {
      fail_call = 6;
      REQUIRE(!actql_native_client_status_watch_end());
      REQUIRE(actql_status_watching && calls == 6);
      REQUIRE(!actql_native_client_status_watch_begin() && calls == 6);
      // The unconfirmed carrier remains pending; exit is not a cleanup ACK.
      puts("{\"case\":\"restore\",\"cleanup\":\"pending\",\"newScope\":false}");
      return 0;
    }
    int64_t before = actql_native_client_status_watch_now();
    REQUIRE(before >= 0);
    REQUIRE(actql_native_client_status_watch_pause(1));
    REQUIRE(actql_native_client_status_watch_now() >= before);
    if (strcmp(argv[1], "interrupted") == 0) {
      REQUIRE(raise(SIGINT) == 0);
      REQUIRE(actql_native_client_status_watch_interrupted());
    } else {
      REQUIRE(strcmp(argv[1], "normal") == 0);
      REQUIRE(!actql_native_client_status_watch_interrupted());
    }
    REQUIRE(actql_native_client_status_watch_end());
    REQUIRE(!actql_status_watching && calls == 6);
  }
  REQUIRE(sigaction(SIGINT, NULL, &observed) == 0 && observed.sa_handler == SIG_IGN);
  REQUIRE(sigaction(SIGTERM, NULL, &observed) == 0 && observed.sa_handler == SIG_IGN);
  printf("{\"case\":\"%s\",\"cleanup\":\"closed\",\"newScope\":false}\n", argv[1]);
  return 0;
}
