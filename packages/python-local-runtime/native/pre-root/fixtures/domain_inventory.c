/* One real selected provider and the product's opaque domain adapter.
 * The finite fixture holding is not a normal command capacity profile. */
#define ACTQL_BOOTSTRAP_IMPORT_PROVIDER 1
#include "../../../../../src/platform_native/host_bootstrap/bootstrap_stub.c"
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

static int checks;
static void require(bool condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL:%s\n", message); exit(2); }
    checks++;
}
static bool empty(const int64_t output[5]) {
    for (size_t index = 0; index < 5; index++) if (output[index] != 0) return false;
    return true;
}
typedef struct {
    actql_bootstrap_domain *domain;
    int status;
    int64_t output[5];
} foreign_observation;
static void *observe_foreign_thread(void *argument) {
    foreign_observation *value = argument;
    value->status = actql_bootstrap_domain_inventory(value->domain, value->output, 5);
    return NULL;
}

int main(void) {
    long page = sysconf(_SC_PAGESIZE);
    char path[] = "/private/tmp/actql-domain-inventory-XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0 || page <= 0 || ftruncate(fd, 64 * page) != 0) return 3;
    printf("fixture:%s\n", path); fflush(stdout);
    unsigned char recipe[32]; memset(recipe, 29, sizeof(recipe));
    actql_bootstrap_backing *parent = actql_bootstrap_acquire_fd(fd, 64 * page, 1, recipe);
    require(actql_bootstrap_status(parent) == 0 && actql_bootstrap_claim(parent, 1, recipe) == 0 &&
        actql_bootstrap_enter_scope(parent) == 0, "original parent entered");
    actql_bootstrap_extent *extent = actql_bootstrap_allocate(parent, 48 * page);
    actql_bootstrap_region *loan = actql_bootstrap_lend_region(parent, extent, 0, 48 * page, 1);
    require(actql_bootstrap_extent_status(extent) == 0 && actql_bootstrap_region_status(loan) == 0 &&
        actql_bootstrap_leave_scope(parent) == 0, "same physical loan retained");
    actql_bootstrap_view *view = actql_bootstrap_map_region(parent, extent, loan, fd, 0, 48 * page);
    actql_bootstrap_domain *domain = actql_bootstrap_acquire_domain(view);
    require(actql_bootstrap_view_status(view) == 0 && actql_bootstrap_domain_status(domain) == 0 &&
        actql_bootstrap_transfer_domain(domain) == 0, "original domain transferred");
    int64_t refused[5] = {0};
    require(actql_bootstrap_domain_inventory(domain, refused, 5) == ACTQL_OWNED_INVALID &&
        empty(refused), "unentered observation refuses without output");
    require(actql_bootstrap_prepare_read_context(domain) == 0 &&
        actql_bootstrap_enter_read_context(domain) == 0, "actual original Read entered");
    int64_t baseline[5] = {0};
    require(actql_bootstrap_domain_inventory(domain, baseline, 5) == 0 &&
        baseline[0] == 48 * page && baseline[1] == page && baseline[2] > 0 &&
        baseline[3] > baseline[2] && baseline[4] >= baseline[3], "atomic same-domain census");
    int64_t short_output[5] = {0}, nonempty[5] = {0, 0, 0, 0, 1};
    require(actql_bootstrap_domain_inventory(domain, short_output, 4) == ACTQL_OWNED_INVALID &&
        empty(short_output) && actql_bootstrap_domain_inventory(domain, nonempty, 5) == ACTQL_OWNED_INVALID &&
        nonempty[0] == 0 && nonempty[4] == 1, "closed output shape and empty-output contract");
    moonbit_bytes_t bytes = moonbit_make_bytes(32, 71);
    int64_t live[5] = {0}, retired[5] = {0};
    require(actql_bootstrap_domain_inventory(domain, live, 5) == 0 &&
        live[3] > baseline[3] && live[4] >= live[3], "live original allocation remains occupied");
    moonbit_decref(bytes);
    require(actql_bootstrap_domain_inventory(domain, retired, 5) == 0 &&
        retired[3] == baseline[3] && retired[4] == live[4], "last release retains historical peak");
    foreign_observation foreign = {.domain = domain}; pthread_t thread;
    require(pthread_create(&thread, NULL, observe_foreign_thread, &foreign) == 0 &&
        pthread_join(thread, NULL) == 0 && foreign.status == ACTQL_OWNED_INVALID &&
        empty(foreign.output), "foreign thread cannot observe original entered lease");
    require(actql_bootstrap_leave_read_context(domain) == 0 &&
        actql_bootstrap_enter_scope(parent) == 0 &&
        actql_bootstrap_domain_inventory(domain, refused, 5) == ACTQL_OWNED_INVALID &&
        empty(refused) && actql_bootstrap_leave_scope(parent) == 0,
        "different actual current holding does not match child");
    require(actql_bootstrap_close_read_context(domain) == 0 &&
        actql_bootstrap_close_domain(view, domain) == 0 &&
        actql_bootstrap_domain_inventory(domain, refused, 5) == ACTQL_OWNED_INVALID && empty(refused) &&
        actql_bootstrap_close_region_view(parent, extent, loan, view) == 0 &&
        actql_bootstrap_return_region(parent, extent, loan) == 0 &&
        actql_bootstrap_retire(parent, extent) == 0 && actql_bootstrap_close(parent) == 0 &&
        fcntl(fd, F_GETFD) >= 0, "closed child refuses while separate cleanup completes");
    moonbit_decref(domain); moonbit_decref(view); moonbit_decref(loan);
    moonbit_decref(extent); moonbit_decref(parent);
    require(close(fd) == 0 && unlink(path) == 0, "original FD closes separately");
    printf("{\"executions\":1,\"checks\":%d,\"normal_profile\":null}\n", checks);
    return checks == 13 ? 0 : 3;
}
