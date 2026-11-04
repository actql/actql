/* Actual same-provider FD/generic/pending census. No Rust allocation, fixed
 * availability value, Core admission or cleanup acknowledgement is supplied. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
static int fail_protection;
static int observed_protect(void *address, size_t bytes, int mode) {
    if (fail_protection) { fail_protection = 0; errno = EIO; return -1; }
    return mprotect(address, bytes, mode);
}
#define mprotect observed_protect
#include "../owned_capacity.c"
#undef mprotect
#define CHECK(name, condition) do { discovered++; \
    if (!(condition)) { fprintf(stderr, "process inventory: %s\n", name); return 1; } \
    passed++; } while (0)

int main(void) {
    int discovered = 0, passed = 0;
    long observed_page = sysconf(_SC_PAGESIZE);
    if (observed_page <= 0) return 2;
    size_t page = (size_t)observed_page;
    char path[] = "/tmp/actql-process-inventory-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0 || unlink(path) || fchmod(fd, 0600) || ftruncate(fd, (off_t)(64 * page))) return 2;
    unsigned char recipe[32] = {41};
    actql_owned_capacity *owner = NULL;
    uint64_t values[16] = {0};
    CHECK("same original private FD", actql_native_owned_acquire_fd(fd, 64 * page, 1, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 1, recipe) == 0);
    CHECK("unentered census refuses", actql_native_owned_inventory(owner, values, 16) == ACTQL_OWNED_INVALID);
    CHECK("same original current", actql_native_owned_enter(owner) == 0);
    CHECK("closed width refuses", actql_native_owned_inventory(owner, values, 15) == ACTQL_OWNED_INVALID);
    values[15] = 1;
    CHECK("nonempty output refuses", actql_native_owned_inventory(owner, values, 16) == ACTQL_OWNED_INVALID && values[0] == 0);
    memset(values, 0, sizeof(values));
    CHECK("actual control footprint", actql_native_owned_inventory(owner, values, 16) == 0 &&
        values[0] == 64 * page && values[1] == page && values[2] == owner->control_pages * page &&
        values[3] == values[2] && values[4] == values[2]);
    size_t controls = (size_t)values[2];
    void *allocation = NULL;
    CHECK("one real rounded generic extent", actql_native_owned_allocate(owner, page + 1, page, &allocation) == 0);
    memset(values, 0, sizeof(values));
    CHECK("census observes actual occupied and peak", actql_native_owned_inventory(owner, values, 16) == 0 &&
        values[3] == controls + 2 * page && values[4] == values[3] &&
        values[5] == 2 * page && values[12] == 1);
    CHECK("no heap records were allocated", values[6] == 0 && values[7] == 0 &&
        values[8] == 0 && values[9] == 0 && values[10] == 0 &&
        values[13] == 0 && values[14] == 0 && values[15] == 0);
    actql_owned_extent_loan loan = {0};
    CHECK("original live loan", actql_native_owned_lend_extent(owner, allocation, false, &loan) == 0);
    CHECK("loan prevents retirement", actql_native_owned_retire(owner, allocation) == ACTQL_OWNED_BUSY);
    CHECK("separate original loan return", actql_native_owned_return_extent(&loan) == 0);
    fail_protection = 1;
    CHECK("failed protection retains pending extent", actql_native_owned_retire(owner, allocation) == ACTQL_OWNED_PHYSICAL_FAILURE);
    memset(values, 0, sizeof(values));
    CHECK("pending remains occupied without payload read", actql_native_owned_inventory(owner, values, 16) == 0 &&
        values[3] == controls + 2 * page && values[11] == 2 * page && values[5] == 0 && values[12] == 0);
    CHECK("same original physical cleanup", actql_native_owned_retire(owner, allocation) == 0);
    memset(values, 0, sizeof(values));
    CHECK("only confirmed retirement changes occupancy", actql_native_owned_inventory(owner, values, 16) == 0 &&
        values[3] == controls && values[4] == controls + 2 * page && values[11] == 0);
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        uint64_t foreign[16] = {0};
        _exit(actql_native_owned_inventory(owner, foreign, 16) == ACTQL_OWNED_INVALID ? 0 : 3);
    }
    int status;
    CHECK("fork cannot adopt census current", waitpid(child, &status, 0) == child &&
        WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK("same owner close leaves caller FD", actql_native_owned_leave(owner) == 0 &&
        actql_native_owned_try_close(&owner) == 0 && owner == NULL && fcntl(fd, F_GETFD) >= 0);
    CHECK("caller separately closes original FD", close(fd) == 0);
    printf("{\"process_inventory_cases\":%d,\"passed\":%d,\"page_bytes\":%zu,"
           "\"observed_control_bytes\":%zu,\"Rust\":0,\"Engine\":0,\"normal_funding\":null}\n",
           discovered, passed, page, controls);
    return discovered == 19 && passed == 19 ? 0 : 3;
}
