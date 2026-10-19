/* Selected derived C bridge only, not a Core issuer, worker or product profile.
 * BOOTSTRAP_SOURCE and ACTQL_SCOPED_READ_PROVIDER are fixed copied inputs. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "moonbit_runtime.h"
#include BOOTSTRAP_SOURCE

typedef struct {
    int fd;
    actql_bootstrap_backing *parent;
    actql_bootstrap_extent *extent;
    actql_bootstrap_region *loan;
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
} fixture;

static const unsigned char recipe[32] = {61};

static fixture open_fixture(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
#if defined(__linux__)
    char path[] = "/tmp/actql-read-bridge-XXXXXX";
#else
    char path[] = "/private/tmp/actql-read-bridge-XXXXXX";
#endif
    fixture f = {0};
    f.fd = mkstemp(path);
    assert(f.fd >= 0 && unlink(path) == 0 && fchmod(f.fd, 0600) == 0);
    assert(ftruncate(f.fd, (off_t)(64 * page)) == 0);
    f.parent = actql_bootstrap_acquire_fd(f.fd, (int64_t)(64 * page), 1, recipe);
    assert(actql_bootstrap_status(f.parent) == 0);
    assert(actql_bootstrap_claim(f.parent, 1, recipe) == 0);
    assert(actql_bootstrap_enter_scope(f.parent) == 0);
    f.extent = actql_bootstrap_allocate(f.parent, (int64_t)(24 * page));
    assert(actql_bootstrap_extent_status(f.extent) == 0);
    f.loan = actql_bootstrap_lend_region(f.parent, f.extent, 0,
                                       (int64_t)(24 * page), 1);
    assert(actql_bootstrap_region_status(f.loan) == 0);
    assert(actql_bootstrap_leave_scope(f.parent) == 0);
    f.view = actql_bootstrap_map_region(f.parent, f.extent, f.loan, f.fd,
                                       (int64_t)page, (int64_t)(16 * page));
    assert(actql_bootstrap_view_status(f.view) == 0);
    f.domain = actql_bootstrap_acquire_domain(f.view);
    assert(actql_bootstrap_domain_status(f.domain) == 0);
    assert(actql_bootstrap_transfer_domain(f.domain) == 0);
    return f;
}

static void close_fixture(fixture *f) {
    assert(actql_bootstrap_close_read_context(f->domain) == 0);
    assert(actql_bootstrap_close_domain(f->view, f->domain) == 0);
    assert(actql_bootstrap_close_region_view(f->parent, f->extent, f->loan, f->view) == 0);
    assert(actql_bootstrap_return_region(f->parent, f->extent, f->loan) == 0);
    assert(actql_bootstrap_retire(f->parent, f->extent) == 0);
    assert(actql_bootstrap_close(f->parent) == 0);
    assert(close(f->fd) == 0);
    f->fd = -1;
    moonbit_decref(f->domain);
    moonbit_decref(f->view);
    moonbit_decref(f->loan);
    moonbit_decref(f->extent);
    moonbit_decref(f->parent);
}

static void case_alias(void) {
    fixture f = open_fixture();
    assert(actql_bootstrap_current_read_context() == NULL);
    assert(actql_bootstrap_prepare_read_context(f.domain) == 0);
    assert(actql_bootstrap_read_context_status(f.domain) == 0);
    assert(actql_bootstrap_prepare_read_context(f.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    assert(actql_bootstrap_current_read_context() == f.domain->read_context);
    moonbit_bytes_t bytes = moonbit_make_bytes(16, 73);
    moonbit_incref(bytes);
    assert(bytes[0] == 73);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(f.domain->read_user && f.domain->read_active == 1);
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(actql_bootstrap_current_read_context() == NULL);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(!f.domain->read_user && f.domain->read_context != NULL);
    moonbit_decref(bytes);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    moonbit_decref(bytes);
    assert(actql_bootstrap_close_read_context(f.domain) == 0);
    assert(f.domain->read_context == NULL);
    close_fixture(&f);
}

static void case_retained_cleanup(void) {
    fixture f = open_fixture();
    assert(actql_bootstrap_prepare_read_context(f.domain) == 0);
    actql_read_context *original = f.domain->read_context;
    // This is an extra C-user stand-in, not actual Root/Reader ACK evidence.
    assert(actql_read_context_retain(original) == 0);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(!f.domain->read_user && f.domain->read_context == original);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    moonbit_bytes_t diagnostic = moonbit_make_bytes(3, 9);
    assert(actql_bootstrap_current_read_context() == original);
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    moonbit_decref(diagnostic);
    assert(actql_bootstrap_close_read_context(f.domain) == ACTQL_OWNED_BUSY);
    assert(actql_read_context_release_after_owner_ack(original) == 0);
    assert(actql_bootstrap_close_read_context(f.domain) == 0);
    close_fixture(&f);
}

static void case_partial_exhaustion(void) {
    fixture f = open_fixture();
    void *held = NULL;
    actql_owned_capacity *original = f.domain->lease;
    uint64_t capacity = 0, control = 0;
    assert(actql_native_owned_capacity_bytes(original, &capacity) == ACTQL_OWNED_OK);
    assert(actql_native_owned_control_bytes(original, &control) == ACTQL_OWNED_OK);
    assert(capacity > control && capacity - control <= SIZE_MAX);
    size_t remaining = (size_t)(capacity - control);
    assert(actql_bootstrap_enter_domain(f.domain) == 0);
    assert(actql_native_owned_allocate(original, remaining, 1, &held) == 0);
    assert(actql_bootstrap_leave_domain(f.domain) == 0);
    assert(actql_bootstrap_prepare_read_context(f.domain) == ACTQL_OWNED_EXHAUSTED);
    assert(f.domain->read_attempted && !f.domain->read_prepare_scope);
    assert(f.domain->read_context == NULL && !f.domain->read_user);
    assert(actql_bootstrap_read_context_status(f.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_prepare_read_context(f.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_close_read_context(f.domain) == 0);
    assert(f.domain->lease == original);
    assert(actql_native_owned_retire(original, held) == 0);
    close_fixture(&f);
}

static void case_original_scope(void) {
    fixture f = open_fixture();
    assert(actql_bootstrap_prepare_read_context(f.domain) == 0);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    assert(actql_bootstrap_enter_read_context(f.domain) == 0);
    assert(f.domain->read_active == 2);
    assert(actql_bootstrap_close_domain(f.view, f.domain) == ACTQL_OWNED_BUSY);
    assert(f.domain->lease != NULL);
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(f.domain->read_active == 1 && actql_bootstrap_current_read_context() != NULL);
    assert(actql_bootstrap_leave_read_context(f.domain) == 0);
    assert(actql_bootstrap_current_read_context() == NULL);
    assert(actql_bootstrap_leave_read_context(f.domain) == ACTQL_OWNED_INVALID);
    assert(actql_bootstrap_close_read_context(f.domain) == 0);
    close_fixture(&f);
}

int main(void) {
    assert(actql_bootstrap_read_supported() == 1);
    case_alias(); puts("{\"case\":\"same-domain-alias\",\"passed\":true}");
    case_retained_cleanup(); puts("{\"case\":\"retained-cleanup\",\"passed\":true}");
    case_partial_exhaustion(); puts("{\"case\":\"partial-exhaustion\",\"passed\":true}");
    case_original_scope(); puts("{\"case\":\"original-scope\",\"passed\":true}");
    puts("{\"success\":true,\"discovered\":4,\"executed\":4,\"passed\":4,\"failed\":0,\"public_e2e\":0}");
    return 0;
}
