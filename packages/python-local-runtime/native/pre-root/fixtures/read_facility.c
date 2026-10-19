/* Same-domain finite allocation facility. No command or funding profile. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/mman.h>
static int fail_protect;
static int facility_protect(void *address, size_t bytes, int protection) {
    if (fail_protect) { fail_protect = 0; errno = EIO; return -1; }
    return mprotect(address, bytes, protection);
}
#define mprotect facility_protect
#ifndef ACTQL_READ_FACILITY_PROVIDER
#define ACTQL_READ_FACILITY_PROVIDER "../owned_capacity.c"
#endif
#include ACTQL_READ_FACILITY_PROVIDER
#undef mprotect
static int cases;
#define CHECK(text, value) do { if (!(value)) { \
    fprintf(stderr, "facility failure: %s\n", text); return 1; } cases++; } while (0)
int main(int argc, char **argv) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char recipe[32] = {61};
    int modes = 3;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    modes = 4;
#endif
    int first = argc == 2 && strcmp(argv[1], "--entered-read") == 0 ? 3 : 0;
    if ((argc != 1 && first == 0) || first >= modes) return 2;
    for (int mode = first; mode < modes; mode++) {
        char path[] = "/tmp/actql-read-facility-XXXXXX";
        int fd = mkstemp(path);
        CHECK("private backing", fd >= 0 && unlink(path) == 0 &&
            fchmod(fd, 0600) == 0 && ftruncate(fd, (off_t)(64 * page)) == 0);
        actql_owned_capacity *parent = NULL, *domain = NULL;
        actql_owned_extent_loan loan = {0};
        actql_owned_extent_reference reference = {0};
        actql_owned_extent_view view = {0};
        void *allocation = NULL;
        CHECK("original parent", actql_native_owned_acquire_fd(fd, 64 * page, 1, recipe, &parent) == 0 &&
            actql_native_owned_transfer(parent, 1, recipe) == 0 &&
            actql_native_owned_enter(parent) == 0);
        CHECK("original domain loan", actql_native_owned_allocate(parent, 24 * page, 1, &allocation) == 0 &&
            actql_native_owned_lend_extent(parent, allocation, true, &loan) == 0 &&
            actql_native_owned_project_extent(&loan, &reference) == 0 &&
            actql_native_owned_map_extent_payload(fd, &reference, page, 16 * page, &view) == 0 &&
            actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
            actql_native_owned_leave(parent) == 0 &&
            actql_native_owned_transfer(domain, 1, recipe) == 0);
        CHECK("unentered refusal", actql_native_owned_bound_allocations(domain, 4 * page) == ACTQL_OWNED_INVALID);
        CHECK("original entered", actql_native_owned_enter(domain) == 0);
        CHECK("foreign refusal", actql_native_owned_bound_allocations(parent, 4 * page) == ACTQL_OWNED_INVALID);
        uint64_t control = 0;
        CHECK("actual control", actql_native_owned_control_bytes(domain, &control) == 0 && control > 0);
        size_t ceiling = (size_t)control + 3 * page;
        void *a = NULL, *b = NULL, *extra = NULL;
        if (mode == 2) {
            CHECK("prior payload", actql_native_owned_allocate(domain, page, 1, &a) == 0 &&
                actql_native_owned_retire(domain, a) == 0);
        }
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
        if (mode == 3) {
            actql_read_context *context = NULL;
            CHECK("bounded original context", actql_native_owned_bound_allocations(domain, ceiling) == 0 &&
                actql_read_context_create(domain, &context) == 0 && actql_read_context_retain(context) == 0 &&
                actql_read_context_enter(context) == 0);
            void *managed = actql_native_moon_scoped_allocate(32);
            void *file = actql_native_file_scoped_allocate(page);
            CHECK("same slab and generic backing", managed != NULL && file != NULL);
            CHECK("entered Read exhaustion has no stock fallback", actql_native_file_scoped_allocate(1) == NULL);
            CHECK("active original refuses cleanup", actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY);
            CHECK("leave does not release escaped allocations", actql_read_context_leave(context) == 0 &&
                actql_read_context_release_after_owner_ack(context) == 0 &&
                actql_read_context_try_close(&context) == ACTQL_OWNED_BUSY && context != NULL);
            actql_native_moon_scoped_free(managed);
            actql_native_file_scoped_free(file);
            CHECK("same aliases retire before context", actql_read_context_try_close(&context) == 0 && context == NULL);
            CHECK("context ACK is not domain ACK", actql_native_owned_leave(domain) == 0 &&
                actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY &&
                actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
        } else
#endif
        if (mode != 0) {
            CHECK("invalid or late selection refuses", actql_native_owned_bound_allocations(domain,
                mode == 1 ? ceiling + 1 : ceiling) == ACTQL_OWNED_INVALID);
            CHECK("failed selection cannot reset or fall through",
                actql_native_owned_bound_allocations(domain, ceiling) == ACTQL_OWNED_INVALID &&
                actql_native_owned_allocate(domain, 1, 1, &extra) == ACTQL_OWNED_EXHAUSTED && extra == NULL);
        } else {
            CHECK("physical bound", actql_native_owned_bound_allocations(domain, ceiling) == 0);
            CHECK("no replacement", actql_native_owned_bound_allocations(domain, 16 * page) == ACTQL_OWNED_INVALID);
            CHECK("rounded simultaneous extents", actql_native_owned_allocate(domain, page + 1, 1, &a) == 0 &&
                actql_native_owned_allocate(domain, page, 1, &b) == 0);
            CHECK("actual exhaustion", actql_native_owned_allocate(domain, 1, 1, &extra) == ACTQL_OWNED_EXHAUSTED && extra == NULL);
            fail_protect = 1;
            CHECK("pending remains occupied", actql_native_owned_retire(domain, a) == ACTQL_OWNED_PHYSICAL_FAILURE &&
                actql_native_owned_allocate(domain, 1, 1, &extra) == ACTQL_OWNED_EXHAUSTED && extra == NULL);
            CHECK("separate surviving allocation cleanup", actql_native_owned_retire(domain, b) == 0);
            CHECK("not a mapping ACK", actql_native_owned_leave(domain) == 0 &&
                actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
            CHECK("same original domain cleanup", actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
        }
        if (mode == 1 || mode == 2) CHECK("same refused domain cleanup", actql_native_owned_leave(domain) == 0 &&
            actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL);
        CHECK("separate view loan parent FD cleanup", actql_native_owned_close_extent_view(&view) == 0 &&
            actql_native_owned_return_extent(&loan) == 0 && actql_native_owned_enter(parent) == 0 &&
            actql_native_owned_retire(parent, allocation) == 0 && actql_native_owned_leave(parent) == 0 &&
            actql_native_owned_try_close(&parent) == 0 && parent == NULL && close(fd) == 0);
    }
    printf("{\"discovered\":%d,\"passed\":%d,\"failed\":0}\n", cases, cases);
    return 0;
}
