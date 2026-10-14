/* Preparation only. Test-only syscall refusals preserve the original allocator,
 * lease and mapping. This is not Wasmtime, a selected profile or a Core Root. */
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>

static int refuse_protect;
static int refuse_unmap;
static int protect_calls;
static int unmap_calls;

static int observed_mprotect(void *address, size_t length, int protection) {
    protect_calls++;
    if (refuse_protect) {
        refuse_protect = 0;
        errno = EIO;
        return -1;
    }
    return mprotect(address, length, protection);
}

static int observed_munmap(void *address, size_t length) {
    unmap_calls++;
    if (refuse_unmap) {
        refuse_unmap = 0;
        errno = EIO;
        return -1;
    }
    return munmap(address, length);
}

#define mprotect observed_mprotect
#define munmap observed_munmap
#include "../owned_capacity.c"
#undef mprotect
#undef munmap

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { \
        fprintf(stderr, "native cleanup case failed: %s\n", name); \
        return 1; \
    } \
    passed++; \
} while (0)

int main(void) {
    int discovered = 0, passed = 0;
    long page_value = sysconf(_SC_PAGESIZE);
    if (page_value <= 0 || (size_t)page_value > SIZE_MAX / 64) return 2;
    size_t page = (size_t)page_value, bytes = page * 64;
    unsigned char recipe[32] = {0};
    actql_owned_capacity *original = NULL;
    void *child = NULL;
    uint64_t capacity = 0;
    CHECK("acquire original", actql_native_owned_acquire(bytes, 7, recipe, &original) == 0);
    actql_owned_capacity *identity = original;
    CHECK("transfer original", actql_native_owned_transfer(original, 7, recipe) == 0);
    CHECK("allocate original child", actql_native_owned_allocate(original, page, 1, &child) == 0);
    refuse_protect = 1;
    CHECK("retirement physical failure", actql_native_owned_retire(original, child) == -2);
    CHECK("failed retirement retains original capacity", original == identity &&
          actql_native_owned_capacity_bytes(original, &capacity) == 0 && capacity == bytes);
    CHECK("enter for membership observation", actql_native_owned_enter(original) == 0);
    CHECK("failed retirement is not a live usable child",
          actql_native_owned_contains_live_span(original, child, 1) == -1);
    CHECK("leave original scope", actql_native_owned_leave(original) == 0);
    int before_protect = protect_calls;
    refuse_protect = 1;
    CHECK("final close retries same child and fails physically",
          actql_native_owned_try_close(&original) == -2 && protect_calls == before_protect + 1);
    CHECK("failed child cleanup does not unmap", original == identity && unmap_calls == 0);
    capacity = 0;
    CHECK("closing retains full capacity", actql_native_owned_capacity_bytes(original, &capacity) == 0 &&
          capacity == bytes && actql_native_owned_enter(original) == -3);
    refuse_unmap = 1;
    CHECK("same close cleans child but original unmap fails",
          actql_native_owned_try_close(&original) == -2 && original == identity && unmap_calls == 1);
    capacity = 0;
    CHECK("unmap failure still holds full original region",
          actql_native_owned_capacity_bytes(original, &capacity) == 0 && capacity == bytes);
    before_protect = protect_calls;
    CHECK("retry same lease without repeating child cleanup",
          actql_native_owned_try_close(&original) == 0 && original == NULL &&
          unmap_calls == 2 && protect_calls == before_protect);
    CHECK("double close performs no syscall",
          actql_native_owned_try_close(&original) == 0 && unmap_calls == 2 &&
          protect_calls == before_protect);
    capacity = 0;
    CHECK("released capacity is unavailable",
          actql_native_owned_capacity_bytes(original, &capacity) == -1 && capacity == 0);
    if (discovered != 16 || passed != 16) return 3;
    printf("{\"native_cleanup_cases\":16,\"passed\":16,\"wasmtime\":0,\"public_e2e\":0}\n");
    return 0;
}
