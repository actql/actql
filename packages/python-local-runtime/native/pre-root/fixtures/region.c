/* Physical same-FD/relative-extent cases; no worker, VM or admission is run. */
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <errno.h>

static int fail_unmap;
static int observed_unmaps;
static int fixture_unmap(void *address, size_t bytes) {
    observed_unmaps++;
    if (fail_unmap) { fail_unmap = 0; errno = EIO; return -1; }
    return munmap(address, bytes);
}
#define munmap fixture_unmap
#include "../owned_capacity.c"
#undef munmap

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { fprintf(stderr, "region case failed: %s\n", name); return 1; } \
    passed++; \
} while (0)

static int private_fd(size_t bytes) {
#if defined(__linux__)
    char path[] = "/tmp/actql-owned-region-XXXXXX";
#else
    char path[] = "/private/tmp/actql-owned-region-XXXXXX";
#endif
    int fd = mkstemp(path);
    if (fd < 0) return -1;
    if (unlink(path) != 0 || fchmod(fd, 0600) != 0 || ftruncate(fd, (off_t)bytes) != 0) {
        close(fd); return -1;
    }
    return fd;
}

int main(void) {
    int discovered = 0, passed = 0;
    long page_value = sysconf(_SC_PAGESIZE);
    if (page_value <= 0 || (size_t)page_value > SIZE_MAX / 64) return 2;
    size_t page = (size_t)page_value, bytes = page * 64;
    int fd = private_fd(bytes), other_fd = private_fd(bytes);
    if (fd < 0 || other_fd < 0) return 2;
    unsigned char recipe[32] = {1};
    actql_owned_capacity *owner = NULL, *duplicate = NULL;
    void *allocation = NULL;
    actql_owned_extent_loan writer = {0}, denied = {0}, reader1 = {0}, reader2 = {0};
    actql_owned_extent_reference extent = {0}, bad = {0};
    actql_owned_extent_view view = {0}, unused = {0};
    CHECK("exact FD acquisition", actql_native_owned_acquire_fd(fd, bytes, 7, recipe, &owner) == 0);
    CHECK("same file cannot reset original", actql_native_owned_acquire_fd(fd, bytes, 7, recipe, &duplicate) == -1 && duplicate == NULL);
    CHECK("original transfer and scope", actql_native_owned_transfer(owner, 7, recipe) == 0 && actql_native_owned_enter(owner) == 0);
    CHECK("original extent", actql_native_owned_allocate(owner, page * 2, 1, &allocation) == 0);
    CHECK("writer loan", actql_native_owned_lend_extent(owner, allocation, true, &writer) == 0);
    CHECK("second writer excluded", actql_native_owned_lend_extent(owner, allocation, true, &denied) == -3 && denied.original == NULL);
    CHECK("reader during writer excluded", actql_native_owned_lend_extent(owner, allocation, false, &denied) == -3);
    CHECK("relative projection", actql_native_owned_project_extent(&writer, &extent) == 0 && extent.length == 2 * page && extent.offset >= page && extent.offset < bytes);
    actql_owned_extent_loan copied = writer;
    CHECK("copied loan cannot return", actql_native_owned_return_extent(&copied) == -1);
    CHECK("copied loan cannot project", actql_native_owned_project_extent(&copied, &bad) == -1);
    CHECK("foreign FD rejected", actql_native_owned_map_extent(other_fd, &extent, &unused) == -5 && unused.original == NULL);
    bad = extent; bad.recipe[0] ^= 1;
    CHECK("foreign recipe rejected", actql_native_owned_map_extent(fd, &bad, &unused) == -5);
    bad = extent; bad.generation++;
    CHECK("foreign generation rejected", actql_native_owned_map_extent(fd, &bad, &unused) == -5);
    bad = extent; bad.offset = 0;
    CHECK("control mapping rejected", actql_native_owned_map_extent(fd, &bad, &unused) == -5);
    bad = extent; bad.offset++;
    CHECK("unaligned mapping rejected", actql_native_owned_map_extent(fd, &bad, &unused) == -5);
    bad = extent; bad.length = bytes;
    CHECK("outside original rejected", actql_native_owned_map_extent(fd, &bad, &unused) == -5);
    CHECK("same FD extent mapping", actql_native_owned_map_extent(fd, &extent, &view) == 0 && view.mapping != allocation && view.length == 2 * page);
    ((unsigned char *)view.mapping)[page + 17] = 91;
    CHECK("same backing bytes", ((unsigned char *)allocation)[page + 17] == 91);
    CHECK("borrowed extent cannot retire", actql_native_owned_retire(owner, allocation) == -3);
    CHECK("borrowed protection cannot change", actql_native_owned_protect(owner, allocation, 0, page, PROT_READ) == -3);
    fail_unmap = 1;
    void *original_mapping = view.mapping;
    CHECK("failed unmap retains same view", actql_native_owned_close_extent_view(&view) == -2 && view.mapping == original_mapping);
    CHECK("failed unmap retains parent loan", actql_native_owned_retire(owner, allocation) == -3);
    CHECK("same view cleanup retry", actql_native_owned_close_extent_view(&view) == 0 && view.mapping == NULL);
    int after_unmap = observed_unmaps;
    CHECK("successful view double close", actql_native_owned_close_extent_view(&view) == 0 && observed_unmaps == after_unmap);
    CHECK("view close does not return parent loan", actql_native_owned_retire(owner, allocation) == -3);
    /* This fixture supplies the retirement ACK explicitly. Production calls
     * only after the existing Owner has confirmed same-child stop/cleanup. */
    CHECK("original loan return", actql_native_owned_return_extent(&writer) == 0);
    CHECK("duplicate loan return refused", actql_native_owned_return_extent(&writer) == -1);
    CHECK("returned projection refused", actql_native_owned_project_extent(&writer, &bad) == -1);
    CHECK("first read loan", actql_native_owned_lend_extent(owner, allocation, false, &reader1) == 0);
    CHECK("second read loan", actql_native_owned_lend_extent(owner, allocation, false, &reader2) == 0);
    CHECK("writer during readers excluded", actql_native_owned_lend_extent(owner, allocation, true, &denied) == -3);
    CHECK("one read return still pending", actql_native_owned_return_extent(&reader1) == 0 && actql_native_owned_retire(owner, allocation) == -3);
    CHECK("leave and pending parent close", actql_native_owned_leave(owner) == 0 && actql_native_owned_try_close(&owner) == -3 && owner != NULL);
    CHECK("closing projection refused", actql_native_owned_project_extent(&reader2, &bad) == -3);
    CHECK("closing mapping refused", actql_native_owned_map_extent(fd, &extent, &unused) == -5);
    CHECK("cleanup return while closing", actql_native_owned_return_extent(&reader2) == 0);
    CHECK("original extent and mapping retire", actql_native_owned_retire(owner, allocation) == 0 && actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    CHECK("provider borrowed FD stays owned by caller", fcntl(fd, F_GETFD) >= 0);
    if (close(fd) != 0 || close(other_fd) != 0) return 2;
    if (discovered != 38 || passed != 38) return 3;
    printf("{\"region_cases\":38,\"passed\":38,\"worker\":0,\"vm\":0,\"public_e2e\":0}\n");
    return 0;
}
