/* Literal same-provider allocation and retirement counters. Fixed64 pages;
 * no Runtime, compiler, Core issuance or numerical product profile. */
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
    if (!(predicate)) { fprintf(stderr, "Rust heap case failed: %s\n", name); return 1; } \
    passed++; } while (0)

struct worker_argument { actql_owned_capacity *owner; int status; };
static void *worker(void *raw) {
    struct worker_argument *arg = raw;
    arg->status = actql_native_owned_enter(arg->owner);
    if (arg->status != 0) return NULL;
    for (int round = 0; round < 2000; round++) {
        void *a = NULL, *b = NULL;
        uint64_t ta = 0, tb = 0;
        if (actql_native_owned_rust_allocate(arg->owner, 424, 8, &a, &ta) != 0 ||
            actql_native_owned_rust_allocate(arg->owner, 88, 8, &b, &tb) != 0 || a == b ||
            actql_native_owned_rust_retire(arg->owner, a, ta) != 0 ||
            actql_native_owned_rust_retire(arg->owner, b, tb) != 0) {
            arg->status = 1;
            break;
        }
    }
    if (actql_native_owned_leave(arg->owner) != 0) arg->status = 1;
    return NULL;
}

int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {1};
    actql_owned_capacity *owner = NULL, *foreign = NULL;
    CHECK("same original64page holding", actql_native_owned_acquire(64 * page, 7, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 7, recipe) == 0);
    void *a = NULL, *b = NULL;
    uint64_t ta = 0, tb = 0;
    CHECK("unbound allocation refuses", actql_native_owned_rust_allocate(owner, 424, 8, &a, &ta) == ACTQL_OWNED_INVALID && a == NULL && ta == 0);
    CHECK("original scope", actql_native_owned_enter(owner) == 0);
    CHECK("first small slot", actql_native_owned_rust_allocate(owner, 424, 8, &a, &ta) == 0 && ta != 0);
    CHECK("neighbor same physical page", actql_native_owned_rust_allocate(owner, 424, 8, &b, &tb) == 0 && tb != ta &&
        (uintptr_t)a / page == (uintptr_t)b / page && (uintptr_t)b - (uintptr_t)a == 512);
    memset(a, 31, 424); memset(b, 47, 424);
    CHECK("generic live-span refuses heap", actql_native_owned_contains_live_span(owner, a, 424) == ACTQL_OWNED_INVALID);
    void *heap_page = (void *)((uintptr_t)a & ~(page - 1));
    CHECK("generic protection refuses heap", actql_native_owned_protect(owner, heap_page, 0, page, PROT_READ) == ACTQL_OWNED_INVALID);
    CHECK("generic retirement refuses heap", actql_native_owned_retire(owner, heap_page) == ACTQL_OWNED_INVALID);
    CHECK("generic readonly seal refuses heap", actql_native_owned_seal_readonly(owner, heap_page) == ACTQL_OWNED_INVALID);
    actql_owned_extent_loan loan = {0};
    CHECK("generic lending refuses heap", actql_native_owned_lend_extent(owner, heap_page, false, &loan) == ACTQL_OWNED_INVALID && loan.original == NULL);
    CHECK("interior pointer refuses", actql_native_owned_rust_retire(owner, (char *)a + 1, ta) == ACTQL_OWNED_INVALID);
    CHECK("neighbor token is not authority", actql_native_owned_rust_retire(owner, a, tb) == ACTQL_OWNED_INVALID);
    CHECK("first slot release preserves neighbor", actql_native_owned_rust_retire(owner, a, ta) == 0 && ((unsigned char *)b)[423] == 47);
    CHECK("stale token refuses", actql_native_owned_rust_retire(owner, a, ta) == ACTQL_OWNED_INVALID);
    void *again = NULL; uint64_t t_again = 0;
    CHECK("reuse has fresh token and zero contents", actql_native_owned_rust_allocate(owner, 424, 8, &again, &t_again) == 0 &&
        again == a && t_again != ta && ((unsigned char *)again)[0] == 0 && ((unsigned char *)again)[423] == 0);
    CHECK("old token after reuse refuses", actql_native_owned_rust_retire(owner, again, ta) == ACTQL_OWNED_INVALID);
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) _exit(actql_native_owned_rust_retire(owner, again, t_again) == ACTQL_OWNED_INVALID ? 0 : 1);
    int child_status = 0;
    CHECK("inherited child cannot retire original slot", waitpid(child, &child_status, 0) == child && WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0 && ((unsigned char *)b)[0] == 47);
    CHECK("foreign original holding", actql_native_owned_acquire(64 * page, 8, recipe, &foreign) == 0 &&
        actql_native_owned_transfer(foreign, 8, recipe) == 0);
    CHECK("foreign lease cannot retire", actql_native_owned_rust_retire(foreign, again, t_again) == ACTQL_OWNED_INVALID);
    void *large = NULL, *aligned = NULL; uint64_t tl = 0, tal = 0;
    CHECK("large stays in original holding", actql_native_owned_rust_allocate(owner, page + 31, 8, &large, &tl) == 0 &&
        (uintptr_t)large >= (uintptr_t)owner && (uintptr_t)large + page + 31 <= (uintptr_t)owner + 64 * page);
    CHECK("large is not generic span", actql_native_owned_contains_live_span(owner, large, 1) == ACTQL_OWNED_INVALID);
    CHECK("large alignment", actql_native_owned_rust_allocate(owner, 19, 2 * page, &aligned, &tal) == 0 && (uintptr_t)aligned % (2 * page) == 0);
    void *refused = NULL; uint64_t tr = 0;
    CHECK("zero bytes refuses", actql_native_owned_rust_allocate(owner, 0, 8, &refused, &tr) == ACTQL_OWNED_INVALID);
    CHECK("nonpower alignment refuses", actql_native_owned_rust_allocate(owner, 1, 3, &refused, &tr) == ACTQL_OWNED_INVALID);
    CHECK("overflow refuses", actql_native_owned_rust_allocate(owner, SIZE_MAX, 8, &refused, &tr) == ACTQL_OWNED_INVALID);
    CHECK("finite allocation failure preserves old", actql_native_owned_rust_allocate(owner, 64 * page, 8, &refused, &tr) == ACTQL_OWNED_EXHAUSTED &&
        refused == NULL && tr == 0 && ((unsigned char *)b)[0] == 47);
    CHECK("large release", actql_native_owned_rust_retire(owner, large, tl) == 0 && actql_native_owned_rust_retire(owner, aligned, tal) == 0);
    CHECK("neighbor release", actql_native_owned_rust_retire(owner, b, tb) == 0);
    size_t old_index = ((uintptr_t)again - (uintptr_t)owner) / page;
    fail_protect = 1;
    CHECK("last slot failed physical retirement retained", actql_native_owned_rust_retire(owner, again, t_again) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        owner->extents[old_index].retired && owner->extents[old_index].rust_class != 0);
    void *other = NULL; uint64_t to = 0;
    CHECK("failed page cannot be reused", actql_native_owned_rust_allocate(owner, 424, 8, &other, &to) == 0 &&
        (uintptr_t)other / page != (uintptr_t)again / page);
    CHECK("remaining slot retires", actql_native_owned_rust_retire(owner, other, to) == 0);
    CHECK("leave original scope", actql_native_owned_leave(owner) == 0);
    pthread_t threads[4]; struct worker_argument args[4] = {{owner,0},{owner,0},{owner,0},{owner,0}};
    int started = 0, joined = 0;
    for (int i = 0; i < 4; i++) { if (pthread_create(&threads[i], NULL, worker, &args[i]) != 0) return 2; started++; }
    for (int i = 0; i < 4; i++) { if (pthread_join(threads[i], NULL) != 0 || args[i].status != 0) return 2; joined++; }
    CHECK("concurrent same-owner slots and retirement", started == 4 && joined == 4);
    void *last = NULL; uint64_t last_token = 0;
    CHECK("original remaining allocation", actql_native_owned_enter(owner) == 0 && actql_native_owned_rust_allocate(owner, 88, 8, &last, &last_token) == 0 && actql_native_owned_leave(owner) == 0);
    CHECK("last actual allocation prevents parent release", actql_native_owned_try_close(&owner) == ACTQL_OWNED_BUSY && owner != NULL);
    CHECK("closing refuses scope but original retirement remains", actql_native_owned_enter(owner) == ACTQL_OWNED_BUSY && actql_native_owned_rust_retire(owner, last, last_token) == 0);
    CHECK("same original failed retirement and holding close", actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    CHECK("foreign unused original closes", actql_native_owned_try_close(&foreign) == 0 && foreign == NULL);
    CHECK("closed idempotence", actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    if (discovered != 39 || passed != 39) return 3;
    printf("{\"native_rust_heap_cases\":39,\"passed\":39,\"wasmtime\":0,\"normal_profile\":null}\n");
    return 0;
}
