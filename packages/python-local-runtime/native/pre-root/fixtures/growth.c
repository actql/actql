/* Actual same-owner segmented mappings. Failure injection changes only the
 * syscall result, never the original owner, ledger decision or generation. */
#include <errno.h>
#include <stdio.h>
#include <sys/mman.h>
static int fail_map, fail_unmap, fail_protect, unmap_calls;
static void *observed_mmap(void *address, size_t length, int protection,
                           int flags, int fd, off_t offset) {
    if (fail_map) { fail_map = 0; errno = ENOMEM; return MAP_FAILED; }
    return mmap(address, length, protection, flags, fd, offset);
}
static int observed_munmap(void *address, size_t length) {
    unmap_calls++;
    if (fail_unmap && --fail_unmap == 0) { errno = EIO; return -1; }
    return munmap(address, length);
}
static int observed_mprotect(void *address, size_t length, int protection) {
    if (fail_protect) { fail_protect = 0; errno = EIO; return -1; }
    return mprotect(address, length, protection);
}
#define mmap observed_mmap
#define munmap observed_munmap
#define mprotect observed_mprotect
#include "../owned_capacity.c"
#undef mmap
#undef munmap
#undef mprotect

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { fprintf(stderr, "growth case failed: %s\n", name); return 1; } \
    passed++; \
} while (0)

int main(void) {
    int discovered = 0, passed = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE), initial = 8 * page;
    unsigned char recipe[32] = {7};
    actql_owned_capacity *owner = NULL;
    uint64_t controls = 0;
    CHECK("acquire and transfer original", actql_native_owned_acquire(initial, 9, recipe, &owner) == 0 &&
          actql_native_owned_transfer(owner, 9, recipe) == 0);
    actql_owned_capacity *identity = owner;
    CHECK("unentered growth refuses", actql_native_owned_grow(owner, initial, initial, &controls) == ACTQL_OWNED_INVALID && controls == 0);
    CHECK("enter original", actql_native_owned_enter(owner) == 0);
    void *old = NULL, *newer = NULL;
    CHECK("fill former finite payload", actql_native_owned_allocate(owner,
          initial - owner->control_pages * page, page, &old) == 0);
    ((unsigned char *)old)[0] = 19;
    CHECK("allocation does not grow implicitly", actql_native_owned_allocate(owner, page, page, &newer) == ACTQL_OWNED_EXHAUSTED && newer == NULL);
    actql_owned_extent_loan old_loan = {0};
    actql_owned_extent_view old_view = {0};
    CHECK("retain old loan and view", actql_native_owned_lend_in_process_extent_range(owner, old, 0, page, true, &old_loan) == 0 &&
          actql_native_owned_view_in_process_extent(&old_loan, 0, page, &old_view) == 0);
    uint64_t before[16] = {0}, after[16] = {0};
    CHECK("observe original", actql_native_owned_inventory(owner, before, 16) == 0);
    fail_map = 1;
    CHECK("refused physical growth", actql_native_owned_grow(owner, initial, 16 * page, &controls) == ACTQL_OWNED_PHYSICAL_FAILURE && controls == 0);
    CHECK("failed acquisition changes no original inventory or serial", actql_native_owned_inventory(owner, after, 16) == 0 &&
          memcmp(before, after, sizeof(before)) == 0 && owner == identity && owner->rust_serial == 0);
    CHECK("actual incremental mapping", actql_native_owned_grow(owner, initial, 16 * page, &controls) == 0 && controls > 0 && controls < 16 * page && owner == identity);
    CHECK("old pointer loan and generation stay current", old_view.mapping == old && ((unsigned char *)old)[0] == 19 &&
          old_loan.extent.generation == 9 && old_loan.extent.capacity == initial && local_view_original(&old_view));
    controls = 0;
    CHECK("lost-result retry cannot acquire twice", actql_native_owned_grow(owner, initial, 16 * page, &controls) == ACTQL_OWNED_INVALID && controls == 0 && owner->length == 24 * page);
    CHECK("new allocation exceeds former entire capacity", actql_native_owned_allocate(owner, 12 * page, page, &newer) == 0);
    CHECK("new segment payload is initially zero", ((unsigned char *)newer)[0] == 0 && ((unsigned char *)newer)[12 * page - 1] == 0);
    ((unsigned char *)newer)[0] = 37;
    CHECK("old and new exact containment", actql_native_owned_contains_live_span(owner, old, page) == 0 &&
          actql_native_owned_contains_live_span(owner, newer, 12 * page) == 0 &&
          actql_native_owned_contains_live_span(owner, newer, 12 * page + 1) == ACTQL_OWNED_INVALID);
    CHECK("segment controls are not payload", actql_native_owned_contains_live_span(owner, owner->segments, 1) == ACTQL_OWNED_INVALID);
    actql_owned_extent_loan new_loan = {0};
    actql_owned_extent_view new_view = {0};
    CHECK("retain same-owner new segment loan", actql_native_owned_lend_in_process_extent_range(owner, newer, 0, page, true, &new_loan) == 0 &&
          actql_native_owned_view_in_process_extent(&new_loan, 0, page, &new_view) == 0 && new_view.mapping == newer && new_loan.owner == old_loan.owner && new_loan.extent.generation == 9);
    CHECK("old and new borrowers prevent retirement", actql_native_owned_retire(owner, old) == ACTQL_OWNED_BUSY &&
          actql_native_owned_retire(owner, newer) == ACTQL_OWNED_BUSY);
    CHECK("active cancellation does not unmap or close", actql_native_owned_try_close(&owner) == ACTQL_OWNED_BUSY && owner == identity && !owner->closing && unmap_calls == 0);
    CHECK("return requires actual view retirement", actql_native_owned_return_extent(&old_loan) == ACTQL_OWNED_BUSY &&
          actql_native_owned_return_extent(&new_loan) == ACTQL_OWNED_BUSY);
    CHECK("old borrower returns unchanged", actql_native_owned_close_extent_view(&old_view) == 0 && actql_native_owned_return_extent(&old_loan) == 0);
    CHECK("new borrower returns unchanged", actql_native_owned_close_extent_view(&new_view) == 0 && actql_native_owned_return_extent(&new_loan) == 0);
    fail_protect = 1;
    CHECK("new segment failed retirement stays owned", actql_native_owned_retire(owner, newer) == ACTQL_OWNED_PHYSICAL_FAILURE &&
          actql_native_owned_contains_live_span(owner, newer, 1) == ACTQL_OWNED_INVALID);
    CHECK("old payload survives new retirement failure", ((unsigned char *)old)[0] == 19 && actql_native_owned_retire(owner, old) == 0);
    controls = 0;
    CHECK("second actual segment on same identity", actql_native_owned_grow(owner, 24 * page, 8 * page, &controls) == 0 && owner == identity);
    CHECK("leave original", actql_native_owned_leave(owner) == 0);
    fail_unmap = 2;
    CHECK("partial close failure retains original and remaining mapping", actql_native_owned_try_close(&owner) == ACTQL_OWNED_PHYSICAL_FAILURE &&
          owner == identity && owner->closing && owner->length == 24 * page && unmap_calls == 2);
    CHECK("closing original cannot reenter", actql_native_owned_enter(owner) == ACTQL_OWNED_BUSY);
    CHECK("same close retry finishes remaining physical cleanup", actql_native_owned_try_close(&owner) == 0 && owner == NULL && unmap_calls == 4);
    printf("{\"native_growth_cases\":%d,\"passed\":%d}\n", discovered, passed);
    return discovered == passed ? 0 : 1;
}
