/* Disposable physical-correlation diagnostic. No VM or resource permission. */
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include "../host_bootstrap/bootstrap_stub.c"

static int cases;
static const char *actor = "parent";
static void require(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "%s live channel failure: %s\n", actor, name); exit(1); }
    printf("case:%s:%d:%s\n", actor, ++cases, name); fflush(stdout);
}
static void send_byte(int fd, char value) { if (write(fd, &value, 1) != 1) exit(4); }
static void receive_byte(int fd, char expected) {
    char value = 0; if (read(fd, &value, 1) != 1 || value != expected) exit(5);
}

int main(void) {
    int fd = 0; size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
    unsigned char recipe[32] = {29};
    actql_bootstrap_backing *backing = actql_bootstrap_acquire_fd(fd, (int64_t)bytes, 1, recipe);
    require(actql_bootstrap_status(backing) == 0 && actql_bootstrap_claim(backing, 1, recipe) == 0 &&
        actql_bootstrap_enter_scope(backing) == 0, "original64page FD and provider scope");
    actql_bootstrap_extent *allocation = actql_bootstrap_allocate(backing, (int64_t)(24 * page));
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(backing, allocation, 0, (int64_t)(24 * page), 1);
    require(actql_bootstrap_region_status(loan) == 0 && actql_bootstrap_leave_scope(backing) == 0,
        "same original allocation and retained physical loan");
    actql_bootstrap_view *view = actql_bootstrap_map_region(backing, allocation, loan, fd,
        (int64_t)page, (int64_t)(16 * page));
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    require(actql_bootstrap_view_status(view) == 0 && actql_bootstrap_domain_status(domain) == 0 &&
        actql_bootstrap_transfer_domain(domain) == 0, "one transferred original child payload");
    int ready[2], resume[2]; if (pipe(ready) || pipe(resume)) return 2;
    pid_t child = fork(); if (child < 0) return 2;
    if (child == 0) {
        actor = "child"; cases = 0; close(ready[0]); close(resume[1]); receive_byte(resume[0], 'B');
        actql_owned_extent_reference ref = loan->loan.extent;
        if (munmap(view->view.mapping, view->view.length) || munmap(backing->lease, bytes)) return 6;
        int64_t material[15] = {1, (int64_t)ref.device, (int64_t)ref.inode,
            (int64_t)ref.capacity, (int64_t)ref.offset, (int64_t)ref.length,
            (int64_t)page, (int64_t)(16 * page), 1, 0, 1, 0, 0, 0, (int64_t)(16 * page)};
        struct actql_domain_borrow_record record = {0}; actql_owned_capacity *holding = NULL;
        require(actql_native_domain_borrow_open(&record, sizeof(record), fd, recipe, material) == 0 &&
            actql_native_domain_borrow_claim_holding(&record, &holding) == 0 &&
            actql_native_domain_borrow_transfer_holding(&record, holding, 1, recipe) == 0,
            "actual child binds the same original FD payload");
        void *value = NULL; uint64_t data[3] = {7, 0, page};
        require(actql_native_domain_borrow_enter(&record) == 0 &&
            actql_native_owned_allocate(holding, page, 1, &value) == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, value, page, &data[1]) == 0 &&
            actql_native_domain_borrow_leave(&record) == 0,
            "same physical allocated span DATA without a VM claim");
        if (write(ready[1], data, sizeof(data)) != sizeof(data)) return 7;
        receive_byte(resume[0], 'C');
        require(actql_native_owned_retire(holding, value) == 0 &&
            actql_native_domain_borrow_close_holding(&record, &holding) == 0 && holding == NULL &&
            fcntl(fd, F_GETFD) >= 0, "mapping retirement does not close the original FD");
        send_byte(ready[1], 'D'); receive_byte(resume[0], 'Q');
        close(fd); close(ready[1]); close(resume[0]);
        return cases == 3 ? 0 : 3;
    }
    close(ready[1]); close(resume[0]);
    actql_bootstrap_live_channel *channel = actql_bootstrap_capture_live_channel(
        domain, (int32_t)child, ready[0], resume[1], 7);
    require(actql_bootstrap_live_channel_status(channel) == 0 &&
        actql_bootstrap_live_vm_current(channel) == ACTQL_OWNED_BUSY,
        "actual pipe capture before span is not VM admission");
    actql_bootstrap_live_channel copy = *channel;
    require(actql_bootstrap_live_channel_status(&copy) == ACTQL_OWNED_INVALID,
        "copied channel cannot impersonate the original physical carrier");
    actql_bootstrap_live_channel *reversed = actql_bootstrap_capture_live_channel(
        domain, (int32_t)child, resume[1], ready[0], 7);
    require(actql_bootstrap_live_channel_status(reversed) == ACTQL_OWNED_INVALID &&
        fcntl(ready[0], F_GETFD) >= 0 && fcntl(resume[1], F_GETFD) >= 0,
        "reversed descriptors refuse without closing caller resources");
    send_byte(resume[1], 'B'); uint64_t data[3] = {0};
    if (read(ready[0], data, sizeof(data)) != sizeof(data)) return 7;
    require(data[0] == 7 && data[1] > 0 && data[2] == page &&
        actql_bootstrap_bind_live_span(channel, (int64_t)data[0], (int64_t)data[1], (int64_t)data[2]) == 0 &&
        actql_bootstrap_live_vm_current(channel) == 0,
        "original private pipe correlates actual child borrow and relative span");
    require(actql_bootstrap_bind_live_span(channel, 7, (int64_t)data[1], (int64_t)data[2])
        == ACTQL_OWNED_INVALID, "same span observation cannot rebind its original channel");
    actql_bootstrap_live_channel *wrong = actql_bootstrap_capture_live_channel(
        domain, (int32_t)child, ready[0], resume[1], 7);
    require(actql_bootstrap_bind_live_span(wrong, 8, (int64_t)data[1], (int64_t)data[2])
        == ACTQL_OWNED_INVALID &&
        actql_bootstrap_bind_live_span(wrong, 7, (int64_t)data[1], (int64_t)data[2])
        == ACTQL_OWNED_INVALID, "wrong nonce consumes only that original binding attempt");
    /* Explicit fixture-owned FD copies test replacement. Production capture
     * itself never dup/open/closes and the Native Owner issues one access. */
    int original_read = dup(ready[0]), replacement[2];
    if (original_read < 0 || pipe(replacement)) return 8;
    actql_bootstrap_live_channel *lifetime = actql_bootstrap_capture_live_channel(
        domain, (int32_t)child, original_read, resume[1], 7);
    require(dup2(replacement[0], ready[0]) == ready[0] &&
        actql_bootstrap_live_channel_status(channel) == ACTQL_OWNED_INVALID &&
        dup2(original_read, ready[0]) == ready[0] &&
        actql_bootstrap_live_channel_status(channel) == ACTQL_OWNED_INVALID,
        "observed descriptor replacement stays refused after restoring equal metadata");
    send_byte(resume[1], 'C'); receive_byte(original_read, 'D'); int status = 0;
    require(waitpid(child, &status, WNOHANG) == 0 &&
        actql_bootstrap_live_channel_status(lifetime) == 0 &&
        atomic_load(&domain->lease->domain_borrower_pid) == 0,
        "original channel lifetime and physical mapping retirement are separate from stop");
    send_byte(resume[1], 'Q');
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 &&
        actql_bootstrap_retire_live_channel_metadata(channel) == 0 &&
        actql_bootstrap_retire_live_channel_metadata(channel) == 0 &&
        fcntl(ready[0], F_GETFD) >= 0 && fcntl(resume[1], F_GETFD) >= 0 && domain->lease != NULL,
        "metadata retirement does not close descriptors domain or parent capacity");
    require(actql_bootstrap_close_domain(view, domain) == 0 &&
        actql_bootstrap_close_region_view(backing, allocation, loan, view) == 0 &&
        actql_bootstrap_return_region(backing, allocation, loan) == 0 &&
        actql_bootstrap_retire(backing, allocation) == 0 && actql_bootstrap_close(backing) == 0 &&
        close(fd) == 0 && close(ready[0]) == 0 && close(resume[1]) == 0 &&
        close(original_read) == 0 && close(replacement[0]) == 0 && close(replacement[1]) == 0,
        "original domain view loan backing and all fixture descriptors close separately");
    printf("{\"success\":true,\"cases\":16,\"parent_cases\":%d,\"child_cases\":3,"
        "\"fixture_pages\":64,\"page_bytes\":%zu,\"VM\":0,\"public_e2e\":0}\n", cases, page);
    return cases == 13 ? 0 : 3;
}
