/* Backing-extent work only, not a capacity or ordinary command profile. */
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
static int fail_protect;
static int observed_protect(void *address, size_t bytes, int mode) {
    if (fail_protect) { fail_protect = 0; errno = EIO; return -1; }
    return mprotect(address, bytes, mode);
}
#define mprotect observed_protect
#include "../owned_capacity.c"
#undef mprotect
#define CHECK(name, predicate) do { discovered++; \
    if (!(predicate)) { fprintf(stderr, "Extent work failed: %s\n", name); return 1; } \
    passed++; } while (0)
int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {3};
    actql_owned_capacity *owner = NULL;
    uint64_t work[5] = {0};
    CHECK("same finite original", actql_native_owned_acquire(64 * page, 1, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 1, recipe) == 0);
    CHECK("unentered observation refuses", actql_native_owned_extent_work(owner, work, 5) == ACTQL_OWNED_INVALID);
    CHECK("original scope", actql_native_owned_enter(owner) == 0);
    CHECK("mapping capacity is not explicit clear work", actql_native_owned_extent_work(owner, work, 5) == 0 &&
        work[0] == 0 && work[1] == 0 && work[2] == 0 && work[3] == 0 && work[4] == 0);
    CHECK("closed width", actql_native_owned_extent_work(owner, work, 4) == ACTQL_OWNED_INVALID);
    work[4] = 1;
    CHECK("nonempty output refuses", actql_native_owned_extent_work(owner, work, 5) == ACTQL_OWNED_INVALID && work[0] == 0);
    memset(work, 0, sizeof(work));
    void *allocation = NULL;
    CHECK("actual rounded allocation", actql_native_owned_allocate(owner, page + 1, page, &allocation) == 0 &&
        actql_native_owned_extent_work(owner, work, 5) == 0 && work[0] == 1 &&
        work[1] == 2 * page && work[2] == 2 * page && work[3] == 0 && work[4] == 0);
    unsigned char *bytes = allocation;
    for (size_t i = 0; i < 2 * page; i++) {
        if (bytes[i] != 0) return 2;
        bytes[i] = 0xa5;
    }
    memset(work, 0, sizeof(work));
    void *failed = NULL;
    fail_protect = 1;
    CHECK("failed protection produces no allocated or zeroed work", actql_native_owned_allocate(owner, page, page, &failed) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        failed == NULL && actql_native_owned_extent_work(owner, work, 5) == 0 &&
        work[0] == 1 && work[1] == 2 * page && work[2] == 2 * page);
    memset(work, 0, sizeof(work));
    fail_protect = 1;
    CHECK("failed original retirement is not counted", actql_native_owned_retire(owner, allocation) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        actql_native_owned_extent_work(owner, work, 5) == 0 && work[3] == 0 && work[4] == 0);
    CHECK("same original retirement", actql_native_owned_retire(owner, allocation) == 0);
    memset(work, 0, sizeof(work));
    CHECK("confirmed retirement remains cumulative", actql_native_owned_extent_work(owner, work, 5) == 0 &&
        work[0] == 1 && work[1] == 2 * page && work[2] == 2 * page && work[3] == 1 && work[4] == 2 * page);
    void *reused = NULL;
    CHECK("same extent reuse", actql_native_owned_allocate(owner, page + 1, page, &reused) == 0 && reused == allocation);
    bytes = reused;
    for (size_t i = 0; i < 2 * page; i++) if (bytes[i] != 0) return 3;
    memset(work, 0, sizeof(work));
    CHECK("secure reuse clears actual rounded bytes again", actql_native_owned_extent_work(owner, work, 5) == 0 &&
        work[0] == 2 && work[1] == 4 * page && work[2] == 4 * page && work[3] == 1 && work[4] == 2 * page);
    CHECK("same original cleanup", actql_native_owned_retire(owner, reused) == 0 &&
        actql_native_owned_leave(owner) == 0 && actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    printf("{\"discovered\":%d,\"passed\":%d,\"reused_bytes_cleared\":%zu}\n", discovered, passed, 2 * page);
    return 0;
}
