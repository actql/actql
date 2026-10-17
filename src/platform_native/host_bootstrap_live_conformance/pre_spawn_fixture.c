/* Disposable conformance pipes only; never linked into the product provider. */
#include <stdint.h>
#include <unistd.h>
static int pipes[4] = {-1, -1, -1, -1};
static int attempted;
int32_t actql_live_fixture_prepare_pipes(void) {
    if (attempted) return -1;
    attempted = 1;
    if (pipe(pipes) || pipe(pipes + 2)) return -1;
    return 0;
}
int32_t actql_live_fixture_pipe(int32_t ordinal) {
    return ordinal == 0 ? pipes[0] : ordinal == 1 ? pipes[3] : -1;
}
int32_t actql_live_fixture_pid(void) { return (int32_t)getpid(); }
int32_t actql_live_fixture_close_pipes(void) {
    int status = 0;
    for (int i = 0; i < 4; i++) {
        int fd = pipes[i];
        pipes[i] = -1;
        if (fd < 0 || close(fd)) status = -1;
    }
    return status;
}
