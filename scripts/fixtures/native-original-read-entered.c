#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include BOOTSTRAP_SOURCE

/* Physical adapter conformance only. These real C loans/scopes do not issue
 * a Common Read claim, installed pair, complete profile or business authority. */
struct original_read_fixture {
    int fd;
    actql_bootstrap_backing *backing;
    actql_bootstrap_extent *extent;
    actql_bootstrap_region *loan;
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
};
static struct original_read_fixture original_new(void) {
    char path[] = "/tmp/actql-read-entered-XXXXXX";
    int fd = mkstemp(path); assert(fd >= 0); assert(unlink(path) == 0);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    assert(ftruncate(fd, (off_t)(64 * page)) == 0);
    unsigned char recipe[32] = {17};
    actql_bootstrap_backing *backing = actql_bootstrap_acquire_fd(fd, 64 * page, 1, recipe);
    assert(actql_bootstrap_status(backing) == 0);
    assert(actql_bootstrap_claim(backing, 1, recipe) == 0);
    assert(actql_bootstrap_enter_scope(backing) == 0);
    actql_bootstrap_extent *extent = actql_bootstrap_allocate(backing, 32 * page);
    assert(actql_bootstrap_extent_status(extent) == 0);
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(backing, extent, 0, 32 * page, 1);
    assert(actql_bootstrap_region_status(loan) == 0);
    actql_bootstrap_view *view = actql_bootstrap_map_region(backing, extent, loan, fd, 0, 32 * page);
    assert(actql_bootstrap_view_status(view) == 0);
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    assert(actql_bootstrap_domain_status(domain) == 0);
    assert(actql_bootstrap_transfer_domain(domain) == 0);
    assert(actql_bootstrap_leave_scope(backing) == 0);
    assert(actql_bootstrap_read_context_entered(domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_prepare_read_context(domain) == 0);
    return (struct original_read_fixture){fd, backing, extent, loan, view, domain};
}
static void original_finish(struct original_read_fixture *value) {
    assert(actql_bootstrap_close_read_context(value->domain) == 0);
    assert(actql_bootstrap_close_domain(value->view, value->domain) == 0);
    assert(actql_bootstrap_close_region_view(value->backing, value->extent, value->loan, value->view) == 0);
    assert(actql_bootstrap_return_region(value->backing, value->extent, value->loan) == 0);
    assert(actql_bootstrap_retire(value->backing, value->extent) == 0);
    assert(actql_bootstrap_close(value->backing) == 0);
    assert(close(value->fd) == 0);
    moonbit_decref(value->domain); moonbit_decref(value->view);
    moonbit_decref(value->loan); moonbit_decref(value->extent);
    moonbit_decref(value->backing);
}
struct foreign_read_observation { actql_bootstrap_domain *domain; int status; };
static void *foreign_read_current(void *raw) {
    struct foreign_read_observation *value = raw;
    value->status = actql_bootstrap_read_context_entered(value->domain);
    return NULL;
}
int main(void) {
    struct original_read_fixture a = original_new(), b = original_new();
    assert(actql_bootstrap_read_context_status(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(a.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_enter_read_context(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(a.domain) == 0);
    struct foreign_read_observation foreign = {a.domain, 999};
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_read_current, &foreign) == 0);
    assert(pthread_join(thread, NULL) == 0 && foreign.status == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_read_context_entered(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(b.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_enter_read_context(a.domain) == 0);
    assert(actql_bootstrap_leave_read_context(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(a.domain) == 0);
    moonbit_bytes_t alias = moonbit_make_bytes_raw(9);
    memcpy(alias, "original!", 9);
    assert(actql_bootstrap_leave_read_context(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(a.domain) == ACTQL_OWNED_INVALID);

    /* Actual scope-loss fault, not an invented success cell. Keep B's original
     * bookkeeping outstanding while its physical frame is absent. */
    assert(actql_bootstrap_enter_read_context(b.domain) == 0);
    assert(actql_read_context_leave(b.domain->read_context) == 0);
    assert(actql_native_owned_leave(b.domain->lease) == 0);
    assert(actql_bootstrap_enter_read_context(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(b.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_read_context_entered(a.domain) == 0);
    assert(actql_bootstrap_leave_read_context(a.domain) == 0);
    /* Restore only that same physical frame to return its original leave. */
    assert(actql_native_owned_enter(b.domain->lease) == 0);
    assert(actql_read_context_enter(b.domain->read_context) == 0);
    assert(actql_bootstrap_leave_read_context(b.domain) == 0);
    original_finish(&b);

    assert(actql_bootstrap_close_read_context(a.domain) == ACTQL_OWNED_BUSY);
    assert(actql_bootstrap_enter_read_context(a.domain) == 0);
    assert(actql_bootstrap_read_context_entered(a.domain) == ACTQL_OWNED_INVALID);
    assert(memcmp(alias, "original!", 9) == 0);
    assert(actql_bootstrap_leave_read_context(a.domain) == 0);
    moonbit_decref(alias);
    original_finish(&a);
    puts("{\"case\":\"same-original-read-entered\",\"passed\":1,\"failed\":0,\"normal_profile\":null}");
    return 0;
}
