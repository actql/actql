/* Relative page extents share one physical allocation, not another allowance. */
#include <stdio.h>
#include <stdlib.h>
#include "../owned_capacity.c"

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { fprintf(stderr, "region range case failed: %s\n", name); return 1; } \
    passed++; \
} while (0)

int main(void) {
    int discovered = 0, passed = 0;
    long page_value = sysconf(_SC_PAGESIZE);
    if (page_value <= 0 || (size_t)page_value > SIZE_MAX / 64) return 2;
    size_t page = (size_t)page_value, bytes = page * 64;
    char path[] = "/tmp/actql-owned-range-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0 || unlink(path) != 0 || fchmod(fd, 0600) != 0 || ftruncate(fd, (off_t)bytes) != 0) return 2;
    unsigned char recipe[32] = {2};
    actql_owned_capacity *owner = NULL;
    void *allocation = NULL;
    actql_owned_extent_loan first = {0}, second = {0}, reader = {0}, shared = {0}, denied = {0};
    actql_owned_extent_reference extent = {0};
    actql_owned_extent_view view = {0};
    CHECK("original setup", actql_native_owned_acquire_fd(fd, bytes, 8, recipe, &owner) == 0 &&
          actql_native_owned_transfer(owner, 8, recipe) == 0 && actql_native_owned_enter(owner) == 0);
    CHECK("one original allocation", actql_native_owned_allocate(owner, 4 * page, 1, &allocation) == 0);
    CHECK("unaligned offset refused", actql_native_owned_lend_extent_range(owner, allocation, 1, page, true, &denied) == -1);
    CHECK("unaligned length refused", actql_native_owned_lend_extent_range(owner, allocation, 0, page - 1, true, &denied) == -1);
    CHECK("zero length refused", actql_native_owned_lend_extent_range(owner, allocation, 0, 0, false, &denied) == -1);
    CHECK("allocation end refused", actql_native_owned_lend_extent_range(owner, allocation, 4 * page, page, true, &denied) == -1);
    CHECK("overflow outside allocation refused", actql_native_owned_lend_extent_range(owner, allocation, 3 * page, 2 * page, true, &denied) == -1);
    CHECK("first page writer", actql_native_owned_lend_extent_range(owner, allocation, 0, page, true, &first) == 0);
    CHECK("disjoint two page writer", actql_native_owned_lend_extent_range(owner, allocation, page, 2 * page, true, &second) == 0);
    CHECK("disjoint reader", actql_native_owned_lend_extent_range(owner, allocation, 3 * page, page, false, &reader) == 0);
    CHECK("overlapping reader shares readonly", actql_native_owned_lend_extent_range(owner, allocation, 3 * page, page, false, &shared) == 0);
    CHECK("partial overlap writer refused", actql_native_owned_lend_extent_range(owner, allocation, 2 * page, 2 * page, true, &denied) == -3 && denied.original == NULL);
    CHECK("read overlap writer refused", actql_native_owned_lend_extent_range(owner, allocation, page, 3 * page, false, &denied) == -3 && denied.original == NULL);
    CHECK("whole allocation writer refused", actql_native_owned_lend_extent(owner, allocation, true, &denied) == -3);
    CHECK("relative range projection", actql_native_owned_project_extent(&second, &extent) == 0 &&
          extent.offset == (size_t)((unsigned char *)allocation - (unsigned char *)owner) + page && extent.length == 2 * page);
    CHECK("relative range mapping", actql_native_owned_map_extent(fd, &extent, &view) == 0 && view.length == 2 * page);
    ((unsigned char *)view.mapping)[0] = 73;
    ((unsigned char *)view.mapping)[2 * page - 1] = 74;
    CHECK("original exact range bytes", ((unsigned char *)allocation)[page] == 73 &&
          ((unsigned char *)allocation)[3 * page - 1] == 74 &&
          ((unsigned char *)allocation)[0] == 0 && ((unsigned char *)allocation)[3 * page] == 0);
    CHECK("view retirement before original return", actql_native_owned_close_extent_view(&view) == 0 &&
          actql_native_owned_return_extent(&first) == 0 && actql_native_owned_return_extent(&second) == 0);
    CHECK("interior readers retain original", actql_native_owned_retire(owner, allocation) == -3);
    CHECK("one interior reader remains", actql_native_owned_return_extent(&reader) == 0 &&
          actql_native_owned_retire(owner, allocation) == -3);
    CHECK("interior borrowed protection refused", actql_native_owned_protect(owner, allocation, 0, page, PROT_READ) == -3);
    CHECK("closing retains interior reader", actql_native_owned_leave(owner) == 0 && actql_native_owned_try_close(&owner) == -3);
    CHECK("same interior cleanup return", actql_native_owned_return_extent(&shared) == 0 &&
          actql_native_owned_retire(owner, allocation) == 0 && actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    if (close(fd) != 0) return 2;
    if (discovered != 23 || passed != 23) return 3;
    printf("{\"region_range_cases\":23,\"passed\":23,\"worker\":0,\"vm\":0,\"public_e2e\":0}\n");
    return 0;
}
