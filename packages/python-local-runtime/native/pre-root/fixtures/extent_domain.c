/* Physical same-provider subdomain only. No worker, VM or Core grant. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
static int fail_protection;
static int domain_mprotect(void *address, size_t length, int protection) {
    if (fail_protection) { --fail_protection; errno = EIO; return -1; }
    return mprotect(address, length, protection);
}
#define mprotect domain_mprotect
#include "../owned_capacity.c"
#undef mprotect

static int cases;
static void require(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "extent domain failure: %s\n", name); exit(1); }
    printf("case:%d:%s\n", ++cases, name);
}

int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
#if defined(__linux__)
    char path[] = "/tmp/actql-extent-domain-XXXXXX";
#else
    char path[] = "/private/tmp/actql-extent-domain-XXXXXX";
#endif
    int fd = mkstemp(path);
    if (fd < 0 || unlink(path) != 0 || fchmod(fd, 0600) != 0 || ftruncate(fd, (off_t)bytes) != 0)
        return 2;
    unsigned char recipe[32] = {17};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    require(actql_native_owned_acquire_fd(fd, bytes, 1, recipe, &parent) == 0 &&
            actql_native_owned_transfer(parent, 1, recipe) == 0 &&
            actql_native_owned_enter(parent) == 0,
            "same original FD provider is current");
    void *allocation = NULL;
    require(actql_native_owned_allocate(parent, 24 * page, 1, &allocation) == 0,
            "original parent allocation covers physical window");
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_reference reference = {0};
    require(actql_native_owned_lend_extent(parent, allocation, true, &loan) == 0 &&
            actql_native_owned_project_extent(&loan, &reference) == 0,
            "same writer loan retains original allocation");
    actql_owned_extent_view view = {0}, readonly = {0};
    require(actql_native_owned_map_extent_payload(fd, &reference, page, 16 * page, &view) == 0,
            "view binds original Core payload separately from page window");
    actql_owned_extent_view copied = view;
    require(actql_native_owned_acquire_extent_domain(&copied, &domain) == ACTQL_OWNED_INVALID &&
            domain == NULL,
            "copied view cannot acquire domain custody");
    actql_owned_extent_reference read_reference = reference;
    read_reference.writable = false;
    /* Deliberately lower access for this trusted negative; DATA alone is not
     * permission and this readonly view cannot become an allocator. */
    require(actql_native_owned_map_extent_payload(fd, &read_reference, page, 16 * page, &readonly) == 0 &&
            actql_native_owned_acquire_extent_domain(&readonly, &domain) == ACTQL_OWNED_INVALID &&
            domain == NULL && actql_native_owned_close_extent_view(&readonly) == 0,
            "readonly view cannot supply allocation domain");
    require(actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
            domain == (void *)((unsigned char *)view.mapping + page) &&
            domain->length == 16 * page && domain->control_pages > 0 &&
            domain->extent_domain && domain->backing_inode == reference.inode,
            "same payload contains bounded local control and original identity");
    actql_owned_capacity *duplicate = NULL;
    require(actql_native_owned_acquire_extent_domain(&view, &duplicate) == ACTQL_OWNED_INVALID &&
            duplicate == NULL && actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY &&
            actql_native_owned_try_close(&domain) == ACTQL_OWNED_INVALID && domain != NULL,
            "live domain cannot be reacquired or unmapped through outer close");
    require(actql_native_owned_leave(parent) == 0 &&
            actql_native_owned_transfer(domain, 1, recipe) == 0 &&
            actql_native_owned_enter(domain) == 0,
            "same provider TLS enters domain after parent scope leaves");
    void *value = NULL;
    require(actql_native_owned_allocate(domain, page, 1, &value) == 0 &&
            actql_native_owned_contains_live_span(domain, value, page) == 0 &&
            (unsigned char *)value >= (unsigned char *)domain + domain->control_pages * page &&
            (unsigned char *)value + page <= (unsigned char *)domain + domain->length &&
            actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && domain != NULL,
            "existing allocator stays inside payload and active scope keeps domain");
    require(actql_native_owned_leave(domain) == 0 &&
            actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY && domain != NULL,
            "unretired original allocation keeps the same closing domain");
    actql_owned_capacity *same = domain;
    fail_protection = 1;
    require(actql_native_owned_retire(domain, value) == ACTQL_OWNED_PHYSICAL_FAILURE &&
            domain == same && view.domain_live,
            "injected physical retirement failure retains original domain and view");
    fail_protection = 1;
    require(actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_PHYSICAL_FAILURE &&
            domain == same && view.domain_live &&
            actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY,
            "failed cleanup preserves pointer and blocks outer unmap");
    require(actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
            actql_native_owned_close_extent_domain(&view, &domain) == 0 && !view.domain_live,
            "same domain retry succeeds once without another allocation");
    require(actql_native_owned_acquire_extent_domain(&view, &duplicate) == ACTQL_OWNED_INVALID &&
            duplicate == NULL && actql_native_owned_close_extent_view(&view) == 0 &&
            actql_native_owned_return_extent(&loan) == 0 &&
            actql_native_owned_enter(parent) == 0 && actql_native_owned_retire(parent, allocation) == 0 &&
            actql_native_owned_leave(parent) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL &&
            fcntl(fd, F_GETFD) >= 0 && close(fd) == 0,
            "same view then parent loan retire without credits or implicit FD close");
    printf("{\"extent_domain_cases\":%d,\"passed\":%d,\"fixture_pages\":64,\"worker\":0,\"vm\":0,\"public_e2e\":0}\n", cases, cases);
    return cases == 15 ? 0 : 3;
}
