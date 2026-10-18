/* Same original allocator, with independent literal placement expectations.
 * Fixed64-page fixture only; no Runtime, Core or numerical product profile. */
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
static int refuse_protect;
static int observed_mprotect(void *address, size_t length, int protection) {
    if (refuse_protect) { refuse_protect = 0; errno = EIO; return -1; }
    return mprotect(address, length, protection);
}
#define mprotect observed_mprotect
#include "../owned_capacity.c"
#undef mprotect

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { fprintf(stderr, "first-fit case failed: %s\n", name); return 1; } \
    passed++; \
} while (0)

int main(void) {
    int discovered = 0, passed = 0;
    long selected = sysconf(_SC_PAGESIZE);
    if (selected <= 0 || (size_t)selected > SIZE_MAX / 64) return 2;
    size_t page = (size_t)selected;
    unsigned char recipe[32] = {0};
    actql_owned_capacity *owner = NULL;
    void *a = NULL, *b = NULL, *c = NULL, *d = NULL, *e = NULL, *f = NULL;
    CHECK("same original acquisition and transfer",
          actql_native_owned_acquire(64 * page, 7, recipe, &owner) == 0 &&
          actql_native_owned_transfer(owner, 7, recipe) == 0);
    CHECK("first single page", actql_native_owned_allocate(owner, 1, 1, &a) == 0);
    ((unsigned char *)a)[0] = 31;
    ((unsigned char *)a)[page - 1] = 47;
    CHECK("adjacent two pages", actql_native_owned_allocate(owner, page + 1, 1, &b) == 0 &&
          b == (unsigned char *)a + page);
    CHECK("next single page", actql_native_owned_allocate(owner, 1, 1, &c) == 0 &&
          c == (unsigned char *)a + 3 * page);
    CHECK("open earlier two-page hole", actql_native_owned_retire(owner, b) == 0);
    CHECK("large request skips undersized earlier hole",
          actql_native_owned_allocate(owner, 3 * page, 1, &d) == 0 &&
          d == (unsigned char *)c + page);
    CHECK("small request still takes earliest hole",
          actql_native_owned_allocate(owner, 1, 1, &e) == 0 && e == b);
    CHECK("following page of same hole remains first-fit",
          actql_native_owned_allocate(owner, 1, 1, &f) == 0 &&
          f == (unsigned char *)b + page);
    void *hole = (uintptr_t)e % (2 * page) == 0 ? f : e;
    CHECK("open unaligned earlier single-page hole", actql_native_owned_retire(owner, hole) == 0);
    void *aligned = NULL;
    uintptr_t tail = (uintptr_t)d + 3 * page;
    uintptr_t expected_aligned = (tail + 2 * page - 1) & ~(2 * page - 1);
    CHECK("alignment skips hole without consuming it",
          actql_native_owned_allocate(owner, 1, 2 * page, &aligned) == 0 &&
          (uintptr_t)aligned == expected_aligned);
    void *replacement = NULL;
    CHECK("unaligned request reuses exact earlier hole",
          actql_native_owned_allocate(owner, 1, 1, &replacement) == 0 && replacement == hole);
    void *rest[64] = {0};
    size_t count = 0;
    int exhausted = ACTQL_OWNED_OK;
    for (; count < 64; count++) {
        exhausted = actql_native_owned_allocate(owner, 1, 1, &rest[count]);
        if (exhausted != ACTQL_OWNED_OK) break;
    }
    CHECK("finite exhaustion keeps empty output", count > 0 && count < 64 &&
          exhausted == ACTQL_OWNED_EXHAUSTED && rest[count] == NULL);
    refuse_protect = 1;
    CHECK("failed physical retirement retains allocated slot",
          actql_native_owned_retire(owner, a) == ACTQL_OWNED_PHYSICAL_FAILURE);
    void *refused = NULL;
    CHECK("failed retirement publishes no free page",
          actql_native_owned_allocate(owner, 1, 1, &refused) == ACTQL_OWNED_EXHAUSTED &&
          refused == NULL);
    CHECK("retry same physical retirement", actql_native_owned_retire(owner, a) == 0);
    void *again = NULL;
    CHECK("confirmed free returns earliest slot after exhaustion",
          actql_native_owned_allocate(owner, 1, 1, &again) == 0 && again == a);
    unsigned char *contents = again;
    CHECK("new allocation is zeroed including old contents", contents[0] == 0 && contents[page - 1] == 0);
    CHECK("live extents refuse owner retirement", actql_native_owned_try_close(&owner) == ACTQL_OWNED_BUSY && owner != NULL);
    refused = NULL;
    CHECK("closing still refuses allocation", actql_native_owned_allocate(owner, 1, 1, &refused) == ACTQL_OWNED_BUSY && refused == NULL);
    CHECK("original live fixed extents retire", actql_native_owned_retire(owner, again) == 0 &&
          actql_native_owned_retire(owner, c) == 0 && actql_native_owned_retire(owner, d) == 0 &&
          actql_native_owned_retire(owner, aligned) == 0 && actql_native_owned_retire(owner, replacement) == 0 &&
          actql_native_owned_retire(owner, hole == e ? f : e) == 0);
    int cleanup = 0;
    for (size_t i = 0; i < count; i++) cleanup |= actql_native_owned_retire(owner, rest[i]);
    CHECK("every original exhaustion extent retires", cleanup == 0);
    CHECK("same owner physically closes", actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    CHECK("repeated closed owner is unchanged", actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    if (discovered != 23 || passed != 23) return 3;
    printf("{\"native_first_fit_cases\":23,\"passed\":23,\"wasmtime\":0,\"public_e2e\":0}\n");
    return 0;
}
