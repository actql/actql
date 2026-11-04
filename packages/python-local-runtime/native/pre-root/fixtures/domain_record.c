/* Physical map/cleanup with explicit PID and syscall fault counters. The real
 * different-process path is exercised separately by the same-provider DLL. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
static pid_t selected_pid;
static pid_t record_pid(void) { return selected_pid; }
static int fail_unmap;
static void *unmap_target;
static int record_unmap(void *p, size_t n) {
    if (p == unmap_target && fail_unmap) { --fail_unmap; errno = EIO; return -1; }
    return munmap(p, n);
}
#define getpid record_pid
#define munmap record_unmap
#include "../owned_capacity.c"
#undef getpid
#undef munmap
static int count;
static void require(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "domain record failure: %s\n", name); exit(1); }
    printf("case:%d:%s\n", ++count, name);
}
int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
    char path[] = "/tmp/actql-domain-record-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0 || unlink(path) || fchmod(fd, 0600) || ftruncate(fd, (off_t)bytes)) return 2;
    selected_pid = 1;
    unsigned char recipe[32] = {29};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    void *allocation = NULL;
    actql_owned_extent_loan loan = {0}; actql_owned_extent_reference ref = {0};
    actql_owned_extent_view view = {0};
    require(actql_native_owned_acquire_fd(fd, bytes, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate(parent, 24 * page, 1, &allocation) == 0 &&
        actql_native_owned_lend_extent(parent, allocation, true, &loan) == 0 &&
        actql_native_owned_project_extent(&loan, &ref) == 0 && actql_native_owned_leave(parent) == 0 &&
        actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer(domain, 1, recipe) == 0, "original parent domain fixture");
    int64_t material[15] = {1, (int64_t)ref.device, (int64_t)ref.inode, (int64_t)bytes,
        (int64_t)ref.offset, (int64_t)ref.length, (int64_t)page, (int64_t)(16 * page),
        1, 2, 1, 1, 3, 0, (int64_t)(16 * page)};
    selected_pid = 2;
    struct actql_domain_borrow_record record = {0};
    require(actql_native_domain_borrow_storage_bytes() == sizeof(record) &&
        actql_native_domain_borrow_storage_alignment() == _Alignof(struct actql_domain_borrow_record) &&
        actql_native_domain_borrow_open(&record, sizeof(record), fd, recipe, material) == 0 &&
        actql_native_domain_borrow_status(&record) == 0, "same record owns original partial map and borrow");
    actql_owned_capacity *holding = NULL, *duplicate = NULL;
    require(actql_native_domain_borrow_claim_holding(&record, &holding) == 0 && holding == record.lease &&
        actql_native_domain_borrow_claim_holding(&record, &duplicate) == ACTQL_OWNED_INVALID && duplicate == NULL &&
        actql_native_domain_borrow_close(&record) == ACTQL_OWNED_INVALID,
        "one original holding blocks second claim and anonymous close");
    require(actql_native_domain_borrow_transfer_holding(&record, holding, 2, recipe) == ACTQL_OWNED_INVALID &&
        actql_native_domain_borrow_transfer_holding(&record, holding, 1, recipe) == 0 &&
        actql_native_domain_borrow_transfer_holding(&record, holding, 1, recipe) == ACTQL_OWNED_INVALID,
        "same local holding transfer preserves original header and is one shot");
    struct actql_domain_borrow_record copied = record;
    require(actql_native_domain_borrow_close(&copied) == ACTQL_OWNED_INVALID &&
        actql_native_domain_borrow_open(&record, sizeof(record), fd, recipe, material) == ACTQL_OWNED_INVALID,
        "copied or consumed record cannot become another borrow");
    actql_owned_capacity *child = NULL;
    require(actql_native_domain_borrow_pointer(&record, &child) == 0 &&
        child == (void *)((unsigned char *)record.view.mapping + page) &&
        actql_native_domain_borrow_enter(&record) == 0 &&
        actql_native_domain_borrow_close_holding(&record, &holding) == ACTQL_OWNED_BUSY &&
        !record.closed && record.lease == child && actql_native_domain_borrow_leave(&record) == 0,
        "active scope retains record and cleanup leave after closing");
    unmap_target = record.view.mapping; fail_unmap = 1;
    require(actql_native_domain_borrow_close_holding(&record, &holding) == ACTQL_OWNED_PHYSICAL_FAILURE &&
        record.lease == NULL && holding == child && record.view.mapping == unmap_target && !record.closed &&
        !record.view.domain_live && atomic_load(&domain->domain_borrower_pid) == 0,
        "failed unmap preserves same record after acknowledged borrow return");
    require(actql_native_domain_borrow_enter(&record) == ACTQL_OWNED_INVALID &&
        actql_native_domain_borrow_close_holding(&record, &holding) == 0 && record.closed && holding == NULL && record.view.mapping == NULL &&
        actql_native_domain_borrow_close_holding(&record, &holding) == 0,
        "retry skips returned borrow and double close never reopens");
    selected_pid = 1;
    require(actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL &&
        actql_native_owned_close_extent_view(&view) == 0 && actql_native_owned_return_extent(&loan) == 0 &&
        actql_native_owned_retire(parent, allocation) == 0 && actql_native_owned_try_close(&parent) == 0 &&
        parent == NULL && fcntl(fd, F_GETFD) >= 0, "parent original retires separately without FD close");
    selected_pid = 2;
    struct actql_domain_borrow_record refused = {0}; material[8] = 0;
    require(actql_native_domain_borrow_open(&refused, sizeof(refused), fd, recipe, material) == ACTQL_OWNED_INVALID &&
        actql_native_domain_borrow_close(&refused) == 0 && refused.closed && close(fd) == 0,
        "pre-map refusal only closes its original empty record");
    printf("{\"domain_record_cases\":%d,\"passed\":%d,\"fixture_pages\":64,\"pid_observation\":\"scalar\",\"unmap_failure\":\"injected\",\"worker\":0,\"vm\":0,\"public_e2e\":0}\n", count, count);
    return count == 10 ? 0 : 3;
}
