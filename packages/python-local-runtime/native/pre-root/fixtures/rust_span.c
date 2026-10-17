/* Read-only physical containment; original allocation tokens still own free. */
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/wait.h>
static int fail_protect;
static int observe_protect(void *address, size_t bytes, int mode) {
    if (fail_protect) { fail_protect = 0; errno = EIO; return -1; }
    return mprotect(address, bytes, mode);
}
#define mprotect observe_protect
#include "../owned_capacity.c"
#undef mprotect
#define CHECK(name, predicate) do { discovered++; \
    if (!(predicate)) { fprintf(stderr, "Rust span case failed: %s\n", name); return 1; } \
    passed++; } while (0)
int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {12};
    actql_owned_capacity *owner = NULL, *foreign = NULL;
    void *a = NULL, *b = NULL, *generic = NULL, *large = NULL;
    uint64_t ta = 0, tb = 0, tl = 0;
    CHECK("original fixed64page holding", actql_native_owned_acquire(64 * page, 1, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 1, recipe) == 0);
    CHECK("unbound observation refuses", actql_native_owned_contains_live_rust_span(owner, owner, 1) == ACTQL_OWNED_INVALID);
    CHECK("original scope and two same-page slots", actql_native_owned_enter(owner) == 0 &&
        actql_native_owned_rust_allocate(owner, 424, 8, &a, &ta) == 0 &&
        actql_native_owned_rust_allocate(owner, 424, 8, &b, &tb) == 0 && (uintptr_t)b - (uintptr_t)a == 512);
    CHECK("original live Rust data", actql_native_owned_contains_live_rust_span(owner, a, 424) == 0 &&
        actql_native_owned_contains_live_rust_span(owner, (char *)a + 40, 384) == 0);
    CHECK("empty or missing input refuses", actql_native_owned_contains_live_rust_span(owner, a, 0) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_rust_span(owner, NULL, 1) == ACTQL_OWNED_INVALID);
    CHECK("cross-slot observation refuses", actql_native_owned_contains_live_rust_span(owner, (char *)a + 511, 2) == ACTQL_OWNED_INVALID);
    CHECK("control and slab metadata refuse", actql_native_owned_contains_live_rust_span(owner, owner, 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_rust_span(owner, (void *)((uintptr_t)a & ~(page - 1)), 1) == ACTQL_OWNED_INVALID);
    CHECK("generic storage is not Rust", actql_native_owned_allocate(owner, page, page, &generic) == 0 &&
        actql_native_owned_contains_live_rust_span(owner, generic, 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_span(owner, generic, page) == 0);
    CHECK("Rust page remains nonexportable", actql_native_owned_contains_live_span(owner, a, 424) == ACTQL_OWNED_INVALID &&
        actql_native_owned_protect(owner, (void *)((uintptr_t)a & ~(page - 1)), 0, page, PROT_READ) == ACTQL_OWNED_INVALID);
    CHECK("foreign holding refuses", actql_native_owned_acquire(64 * page, 2, recipe, &foreign) == 0 &&
        actql_native_owned_contains_live_rust_span(foreign, a, 1) == ACTQL_OWNED_INVALID);
    CHECK("one original large Rust allocation", actql_native_owned_rust_allocate(owner, page + 1, page, &large, &tl) == 0 &&
        actql_native_owned_contains_live_rust_span(owner, (char *)large + page - 3, 8) == 0);
    CHECK("cross-large extent refuses", actql_native_owned_contains_live_rust_span(owner, (char *)large + 2 * page - 1, 2) == ACTQL_OWNED_INVALID);
    CHECK("large remains non-generic", actql_native_owned_contains_live_span(owner, large, page + 1) == ACTQL_OWNED_INVALID);
    CHECK("retired slot refuses while neighbor lives", actql_native_owned_rust_retire(owner, a, ta) == 0 &&
        actql_native_owned_contains_live_rust_span(owner, a, 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_contains_live_rust_span(owner, b, 424) == 0);
    void *replacement = NULL; uint64_t next_token = 0;
    CHECK("physical reuse is not original token authority", actql_native_owned_rust_allocate(owner, 424, 8, &replacement, &next_token) == 0 &&
        replacement == a && next_token != ta && actql_native_owned_contains_live_rust_span(owner, replacement, 424) == 0 &&
        actql_native_owned_rust_retire(owner, a, ta) == ACTQL_OWNED_INVALID);
    CHECK("original replacement token retires", actql_native_owned_rust_retire(owner, replacement, next_token) == 0);
    fail_protect = 1;
    CHECK("failed final retirement remains refused", actql_native_owned_rust_retire(owner, b, tb) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        actql_native_owned_contains_live_rust_span(owner, b, 1) == ACTQL_OWNED_INVALID);
    pid_t child = fork(); if (child < 0) return 2;
    if (child == 0) _exit(actql_native_owned_contains_live_rust_span(owner, large, 1) == ACTQL_OWNED_INVALID ? 0 : 1);
    int status = 0;
    CHECK("fork does not re-adopt current", waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK("same original remaining cleanup", actql_native_owned_rust_retire(owner, large, tl) == 0 &&
        actql_native_owned_retire(owner, generic) == 0 && actql_native_owned_leave(owner) == 0);
    CHECK("unbound after leave refuses", actql_native_owned_contains_live_rust_span(owner, a, 1) == ACTQL_OWNED_INVALID);
    CHECK("pending physical retry closes same originals", actql_native_owned_try_close(&owner) == 0 && owner == NULL &&
        actql_native_owned_try_close(&foreign) == 0 && foreign == NULL);
    printf("{\"native_rust_span_cases\":%d,\"passed\":%d,\"Runtime\":0,\"normal_profile\":null}\n", discovered, passed);
    return 0;
}
