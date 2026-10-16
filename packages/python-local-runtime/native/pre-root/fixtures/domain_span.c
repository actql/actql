/* Actual same-provider span DATA only. No VM, worker grant or numerical profile. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include "../owned_capacity.c"

static int cases;
static const char *actor = "parent";
static void require(int condition, const char *name) {
    if (!condition) { fprintf(stderr, "%s span failure: %s\n", actor, name); exit(1); }
    printf("case:%s:%d:%s\n", actor, ++cases, name); fflush(stdout);
}
static void send_byte(int fd, char value) { if (write(fd, &value, 1) != 1) exit(4); }
static void receive_byte(int fd, char expected) {
    char value = 0; if (read(fd, &value, 1) != 1 || value != expected) exit(5);
}

int main(void) {
    int fd = 0;
    size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = 64 * page;
    unsigned char recipe[32] = {29};
    actql_owned_capacity *parent = NULL, *domain = NULL;
    actql_owned_extent_loan loan = {0};
    actql_owned_extent_reference ref = {0};
    actql_owned_extent_view view = {0};
    void *allocation = NULL;
    require(actql_native_owned_acquire_fd(fd, bytes, 1, recipe, &parent) == 0 &&
        actql_native_owned_transfer(parent, 1, recipe) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_allocate(parent, 24 * page, 1, &allocation) == 0 &&
        actql_native_owned_lend_extent(parent, allocation, true, &loan) == 0 &&
        actql_native_owned_project_extent(&loan, &ref) == 0 && actql_native_owned_leave(parent) == 0,
        "original64page FD and one retained parent loan");
    require(actql_native_owned_map_extent_payload(fd, &ref, page, 16 * page, &view) == 0 &&
        actql_native_owned_acquire_extent_domain(&view, &domain) == 0 &&
        actql_native_owned_transfer(domain, 1, recipe) == 0,
        "one original initialized16page child payload");
    int ready[2], resume[2]; if (pipe(ready) || pipe(resume)) return 2;
    pid_t child = fork(); if (child < 0) return 2;
    if (child == 0) {
        actor = "child"; cases = 0; close(ready[0]); close(resume[1]);
        if (munmap(view.mapping, view.length) || munmap(parent, bytes)) return 6;
        struct actql_domain_borrow_record record = {0};
        int64_t material[15] = {1, (int64_t)ref.device, (int64_t)ref.inode,
            (int64_t)ref.capacity, (int64_t)ref.offset, (int64_t)ref.length,
            (int64_t)page, (int64_t)(16 * page), 1, 0, 1, 0, 0, 0, (int64_t)(16 * page)};
        actql_owned_capacity *holding = NULL;
        uint64_t offset = 0;
        require(actql_native_domain_borrow_open(&record, sizeof(record), fd, recipe, material) == 0 &&
            actql_native_domain_borrow_span_offset(&record, record.lease, record.lease, page, &offset)
                == ACTQL_OWNED_INVALID && offset == 0,
            "same borrowed record before holding transfer cannot project");
        require(actql_native_domain_borrow_claim_holding(&record, &holding) == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, holding, page, &offset)
                == ACTQL_OWNED_INVALID && offset == 0,
            "claimed but untransferred holding cannot project");
        require(actql_native_domain_borrow_transfer_holding(&record, holding, 1, recipe) == 0 &&
            actql_native_domain_borrow_enter(&record) == 0,
            "same original holding transfer and physical scope");
        void *value = NULL;
        require(actql_native_owned_allocate(holding, 2 * page, 1, &value) == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, value, 2 * page, &offset) == 0 &&
            offset == (uint64_t)((unsigned char *)value - (unsigned char *)holding),
            "one actual allocated span projects its relative offset only");
        uint64_t interior = 0;
        require(actql_native_domain_borrow_span_offset(&record, holding,
            (unsigned char *)value + 1, 2 * page - 1, &interior) == 0 && interior == offset + 1,
            "interior span remains within the same live allocation");
        uint64_t rejected = 0;
        require(actql_native_domain_borrow_span_offset(&record, holding,
            value, 2 * page + 1, &rejected) == ACTQL_OWNED_INVALID && rejected == 0 &&
            actql_native_domain_borrow_span_offset(&record, NULL,
            value, page, &rejected) == ACTQL_OWNED_INVALID,
            "cross allocation and foreign holding refuse without output");
        struct actql_domain_borrow_record copied = record;
        require(actql_native_domain_borrow_span_offset(&copied, holding, value, page, &rejected)
                == ACTQL_OWNED_INVALID && rejected == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, value, page, &offset)
                == ACTQL_OWNED_INVALID,
            "copied record and nonempty output cannot impersonate an observation");
        require(actql_native_domain_borrow_leave(&record) == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, value, page, &rejected)
                == ACTQL_OWNED_INVALID && rejected == 0,
            "relative observation cannot escape the original active scope");
        require(actql_native_domain_borrow_close_holding(&record, &holding) == ACTQL_OWNED_BUSY &&
            holding != NULL && record.closing,
            "live allocated span keeps the same failed cleanup carrier");
        /* Closing permits only existing physical cleanup through the retained
         * lease. The span DATA itself is not permission to enter a new scope. */
        require(actql_native_owned_retire(holding, value) == 0 &&
            actql_native_domain_borrow_span_offset(&record, holding, value, page, &rejected)
                == ACTQL_OWNED_INVALID && rejected == 0,
            "retired allocation cannot be revived from old span DATA");
        require(actql_native_domain_borrow_close_holding(&record, &holding) == 0 && holding == NULL &&
            actql_native_domain_borrow_span_offset(&record, holding, value, page, &rejected)
                == ACTQL_OWNED_INVALID && fcntl(fd, F_GETFD) >= 0,
            "same physical retry retires only the mapping and not its FD");
        send_byte(ready[1], 'D'); receive_byte(resume[0], 'C');
        close(fd); close(ready[1]); close(resume[0]);
        return cases == 11 ? 0 : 3;
    }
    close(ready[1]); close(resume[0]); receive_byte(ready[0], 'D');
    int status = 0;
    require(waitpid(child, &status, WNOHANG) == 0 && domain->closing &&
        atomic_load(&domain->domain_borrower_pid) == 0,
        "physical mapping retirement is separate from actual child stop");
    send_byte(resume[1], 'C');
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 &&
        actql_native_owned_close_extent_domain(&view, &domain) == 0 && domain == NULL,
        "same original child stop then parent domain close");
    require(actql_native_owned_close_extent_view(&view) == 0 &&
        actql_native_owned_return_extent(&loan) == 0 && actql_native_owned_enter(parent) == 0 &&
        actql_native_owned_retire(parent, allocation) == 0 && actql_native_owned_leave(parent) == 0 &&
        actql_native_owned_try_close(&parent) == 0 && parent == NULL &&
        close(fd) == 0 && close(ready[0]) == 0 && close(resume[1]) == 0,
        "separate original view loan backing and FD retirement");
    printf("{\"success\":true,\"cases\":16,\"parent_cases\":%d,\"child_cases\":11,"
        "\"page_bytes\":%zu,\"fixture_pages\":64,\"VM\":0,\"public_e2e\":0}\n", cases, page);
    return cases == 5 ? 0 : 3;
}
