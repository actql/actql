/* Physical occupancy counters only; no Runtime, image or funding profile. */
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
    if (!(predicate)) { fprintf(stderr, "Inventory case failed: %s\n", name); return 1; } \
    passed++; } while (0)
int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {2};
    actql_owned_capacity *owner = NULL, *foreign = NULL;
    uint64_t inventory[16] = {0};
    CHECK("original64page holding", actql_native_owned_acquire(64 * page, 1, recipe, &owner) == 0 &&
        actql_native_owned_transfer(owner, 1, recipe) == 0);
    CHECK("unbound observation refuses", actql_native_owned_inventory(owner, inventory, 16) == ACTQL_OWNED_INVALID && inventory[0] == 0);
    CHECK("original scope", actql_native_owned_enter(owner) == 0);
    CHECK("closed output width", actql_native_owned_inventory(owner, inventory, 15) == ACTQL_OWNED_INVALID && inventory[0] == 0);
    inventory[15] = 1;
    CHECK("nonempty output refuses", actql_native_owned_inventory(owner, inventory, 16) == ACTQL_OWNED_INVALID && inventory[0] == 0 && inventory[15] == 1);
    memset(inventory, 0, sizeof(inventory));
    CHECK("baseline includes control", actql_native_owned_inventory(owner, inventory, 16) == 0 &&
        inventory[0] == 64 * page && inventory[1] == page && inventory[2] == page &&
        inventory[3] == page && inventory[4] == page && inventory[5] == 0 && inventory[11] == 0);
    CHECK("foreign holding refuses", actql_native_owned_acquire(64 * page, 2, recipe, &foreign) == 0 &&
        actql_native_owned_inventory(foreign, (uint64_t[16]){0}, 16) == ACTQL_OWNED_INVALID);
    void *generic = NULL, *small = NULL, *large = NULL;
    uint64_t small_token = 0, large_token = 0;
    CHECK("literal occupied allocations", actql_native_owned_allocate(owner, page + 1, page, &generic) == 0 &&
        actql_native_owned_rust_allocate(owner, 424, 8, &small, &small_token) == 0 &&
        actql_native_owned_rust_allocate(owner, page + 1, 8, &large, &large_token) == 0);
    memset(inventory, 0, sizeof(inventory));
    CHECK("nonoverlapping physical partition", actql_native_owned_inventory(owner, inventory, 16) == 0 &&
        inventory[3] == 6 * page && inventory[4] == 6 * page && inventory[5] == 2 * page &&
        inventory[6] == page && inventory[7] == 2 * page && inventory[11] == 0 &&
        inventory[2] + inventory[5] + inventory[6] + inventory[7] + inventory[11] == inventory[3]);
    CHECK("slab details are contained bytes", inventory[8] == 2096 && inventory[9] == 512 &&
        inventory[10] == 26 * 512 && inventory[12] == 1 && inventory[13] == 1 &&
        inventory[14] == 1 && inventory[15] == 1 && inventory[8] + inventory[9] + inventory[10] <= inventory[6]);
    CHECK("last large retirement", actql_native_owned_rust_retire(owner, large, large_token) == 0);
    memset(inventory, 0, sizeof(inventory));
    CHECK("peak is not current or credit", actql_native_owned_inventory(owner, inventory, 16) == 0 &&
        inventory[3] == 4 * page && inventory[4] == 6 * page && inventory[7] == 0);
    fail_protect = 1;
    CHECK("failed physical slab retirement", actql_native_owned_rust_retire(owner, small, small_token) == ACTQL_OWNED_PHYSICAL_FAILURE);
    memset(inventory, 0, sizeof(inventory));
    CHECK("pending remains occupied without payload read", actql_native_owned_inventory(owner, inventory, 16) == 0 &&
        inventory[3] == 4 * page && inventory[4] == 6 * page && inventory[11] == page &&
        inventory[6] == 0 && inventory[8] == 0 && inventory[15] == 0 &&
        inventory[2] + inventory[5] + inventory[11] == inventory[3]);
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) _exit(actql_native_owned_inventory(owner, (uint64_t[16]){0}, 16) == ACTQL_OWNED_INVALID ? 0 : 1);
    int child_status = 0;
    CHECK("fork cannot adopt observational scope", waitpid(child, &child_status, 0) == child &&
        WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0);
    CHECK("generic cleanup before original leave", actql_native_owned_retire(owner, generic) == 0 &&
        actql_native_owned_leave(owner) == 0);
    CHECK("same original pending cleanup and close", actql_native_owned_try_close(&owner) == 0 && owner == NULL &&
        actql_native_owned_try_close(&foreign) == 0 && foreign == NULL);
    printf("{\"discovered\":%d,\"passed\":%d,\"holding_bytes\":%zu,\"extent_bytes\":%zu,\"slab_metadata_bytes\":%zu}\n",
        discovered, passed, sizeof(actql_owned_capacity), sizeof(struct extent), sizeof(struct rust_heap_page));
    return 0;
}
