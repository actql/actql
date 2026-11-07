/* Same-provider physical alias only; not a worker, grant or process profile. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include "../owned_capacity.c"
static int cases;
static const char *actor = "parent";
static void require(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "%s domain borrow failure: %s\n", actor, name); exit(1); }
    printf("case:%s:%d:%s\n", actor, ++cases, name); fflush(stdout);
}
static void byte(int fd, char value) { if (write(fd, &value, 1) != 1) exit(4); }
static void receive(int fd, char expected) {
    char value = 0; if (read(fd, &value, 1) != 1 || value != expected) exit(5);
}
int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
    char path[] = "/tmp/actql-domain-borrow-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0 || unlink(path) || fchmod(fd, 0600) || ftruncate(fd, (off_t)bytes)) return 2;
    unsigned char recipe[32] = {29};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *allocation = NULL, *original_value = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_reference ref = {0};
    actql_owned_extent_view view = {0};
    require(actql_native_owned_acquire_fd(fd, bytes, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate(parent, 24 * page, 1, &allocation) == 0 &&
        actql_native_owned_lend_extent(parent, allocation, true, &loan) == 0 &&
        actql_native_owned_project_extent(&loan, &ref) == 0 && actql_native_owned_leave(parent) == 0,
        "original FD loan and separate physical window");
    require(actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer(domain, 1, recipe) == 0 && actql_native_owned_enter(domain) == 0 &&
        actql_native_owned_allocate(domain, page, 1, &original_value) == 0 &&
        actql_native_owned_leave(domain) == 0, "original initialized allocator with retained allocation");
    require(actql_native_owned_domain_matches_view(domain, &view, getpid()) == 0 &&
        actql_native_owned_domain_matches_view(domain, &view, getpid() + 1) == ACTQL_OWNED_INVALID &&
        actql_native_owned_transfer_original_domain(domain) == ACTQL_OWNED_INVALID,
        "opaque original view check does not renew an already transferred domain");
    memset(original_value, 73, page);
    size_t value_offset = (size_t)((unsigned char *)original_value - (unsigned char *)domain);
    actql_owned_extent_view alias = {0}; actql_owned_capacity *other = NULL;
    require(actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &alias) == 0 &&
        actql_native_owned_borrow_extent_domain(&alias, &other) == ACTQL_OWNED_IMAGE_MISMATCH &&
        other == NULL && actql_native_owned_close_extent_view(&alias) == 0,
        "same-process alias cannot become a child borrow");
    int ready[2], resume[2]; if (pipe(ready) || pipe(resume)) return 2;
    pid_t child = fork(); if (child < 0) return 2;
    if (child == 0) {
        actor = "child"; cases = 0; close(ready[0]); close(resume[1]);
        /* Fork is solely the physical diagnostic launcher. Do not use the
         * inherited parent mappings or its allocator/control lock. */
        if (munmap(view.mapping, view.length) || munmap(parent, bytes)) return 6;
        actql_owned_extent_view selected = {0}; actql_owned_capacity *borrow = NULL;
        require(actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &selected) == 0,
            "child maps original FD window only");
        require(actql_native_owned_acquire_extent_domain(&selected, &borrow) == ACTQL_OWNED_IMAGE_MISMATCH &&
            borrow == NULL, "initialized payload is not reacquired or reset");
        actql_owned_extent_view copied = selected;
        require(actql_native_owned_borrow_extent_domain(&copied, &borrow) == ACTQL_OWNED_INVALID &&
            borrow == NULL, "copied view cannot acquire original borrow");
        require(actql_native_owned_borrow_extent_domain(&selected, &borrow) == 0 &&
            borrow->domain_origin_pid == getppid() && borrow->length == 16 * page &&
            ((unsigned char *)borrow)[value_offset] == 73 &&
            borrow->extents[value_offset / page].pages == 1,
            "borrow preserves original header records and bytes");
        require(actql_native_owned_domain_matches_view(borrow, &selected, getpid()) == ACTQL_OWNED_INVALID &&
            actql_native_owned_domain_has_child(borrow, getppid(), getpid()) == ACTQL_OWNED_INVALID,
            "child cannot claim the original parent physical observation");
        byte(ready[1], 'R'); receive(resume[0], 'C');
        void *value = NULL;
        require(actql_native_owned_enter(borrow) == 0 &&
            actql_native_owned_allocate(borrow, page, 1, &value) == 0 &&
            value != (void *)((unsigned char *)borrow + value_offset) &&
            actql_native_owned_contains_live_span(borrow, value, page) == 0 &&
            actql_native_owned_return_extent_domain_borrow(&selected, &borrow) == ACTQL_OWNED_BUSY &&
            borrow != NULL && actql_native_owned_leave(borrow) == 0,
            "same provider allocation and active-scope retirement refusal");
        require(actql_native_owned_return_extent_domain_borrow(&selected, &borrow) == ACTQL_OWNED_BUSY &&
            borrow != NULL && selected.domain_live &&
            actql_native_owned_close_extent_domain(&selected, &borrow) == ACTQL_OWNED_INVALID &&
            actql_native_owned_close_extent_view(&selected) == ACTQL_OWNED_BUSY,
            "live allocations retain borrow and block parent-domain or view close");
        require(actql_native_owned_retire(borrow, value) == 0 &&
            actql_native_owned_retire(borrow, (unsigned char *)borrow + value_offset) == 0 &&
            actql_native_owned_return_extent_domain_borrow(&selected, &borrow) == 0 && borrow == NULL &&
            actql_native_owned_return_extent_domain_borrow(&selected, &borrow) == 0,
            "same original retirement clears local slot once");
        actql_owned_capacity *again = NULL;
        require(actql_native_owned_borrow_extent_domain(&selected, &again) == ACTQL_OWNED_INVALID &&
            actql_native_owned_close_extent_view(&selected) == 0 &&
            fcntl(fd, F_GETFD) >= 0 && close(fd) == 0,
            "closed original cannot restart and FD retirement is separate");
        byte(ready[1], 'D'); close(ready[1]); close(resume[0]);
        return cases == 9 ? 0 : 3;
    }
    close(ready[1]); close(resume[0]); receive(ready[0], 'R');
    require(actql_native_owned_domain_matches_view(domain, &view, getpid()) == 0 &&
        actql_native_owned_domain_has_child(domain, getpid(), child) == 0 &&
        actql_native_owned_domain_has_child(domain, getpid(), child + 1) == ACTQL_OWNED_INVALID,
        "parent observes only its same actual child without locking the borrowed allocator");
    void *attempt = NULL; uint64_t held = 0;
    require(actql_native_owned_enter(domain) == ACTQL_OWNED_BUSY &&
        actql_native_owned_allocate(domain, page, 1, &attempt) == ACTQL_OWNED_BUSY && attempt == NULL &&
        actql_native_owned_retire(domain, original_value) == ACTQL_OWNED_BUSY &&
        actql_native_owned_capacity_bytes(domain, &held) == ACTQL_OWNED_BUSY && held == 0,
        "parent cannot enter allocate retire or lock a borrowed domain");
    actql_owned_capacity *same = domain;
    require(actql_native_owned_close_extent_domain(&view, &domain) == ACTQL_OWNED_BUSY &&
        domain == same && view.domain_live && !domain->closing &&
        actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY,
        "parent close keeps original without changing child closing state");
    byte(resume[1], 'C'); receive(ready[0], 'D');
    int status = 0;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 &&
        atomic_load(&domain->domain_borrower_pid) == 0 && domain->domain_borrow_attempted && domain->closing,
        "child returns original physical borrow before separately observed process exit");
    actql_owned_extent_view fresh = {0}; actql_owned_capacity *unused = NULL;
    require(actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &fresh) == 0 &&
        actql_native_owned_acquire_extent_domain(&fresh, &unused) == ACTQL_OWNED_IMAGE_MISMATCH &&
        unused == NULL && actql_native_owned_close_extent_view(&fresh) == 0 &&
        actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL,
        "retired initialized payload is not new capacity");
    require(actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_enter(parent) == 0 && actql_native_owned_retire(parent, allocation) == 0 &&
        actql_native_owned_leave(parent) == 0 && actql_native_owned_try_close(&parent) == 0 && parent == NULL &&
        close(fd) == 0 && close(ready[0]) == 0 && close(resume[1]) == 0,
        "original parent domain view loan and FD close separately");
    printf("{\"domain_borrow_cases\":19,\"parent_cases\":%d,\"child_cases\":9,\"passed\":19,\"fixture_pages\":64,\"worker\":0,\"vm\":0,\"public_e2e\":0}\n", cases);
    return cases == 10 ? 0 : 3;
}
