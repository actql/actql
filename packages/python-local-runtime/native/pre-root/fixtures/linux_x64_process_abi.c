/* Actual selected C layout/atomic observation, not a Core grant or normal
 * profile acceptance. The original region/domain fixtures cover custody. */
#include <assert.h>
#include <stdio.h>
#include "../owned_capacity.c"

int main(void) {
    long page = sysconf(_SC_PAGESIZE);
    assert(page > 0);
    unsigned char recipe[32] = {19};
    actql_owned_capacity *owner = NULL;
    assert(actql_native_owned_acquire((size_t)page * 64, 1, recipe, &owner) == 0);
    assert(atomic_is_lock_free(&owner->domain_borrower_pid));
    assert(atomic_is_lock_free(&owner->rust_process));
    assert(actql_native_owned_enter(owner) == 0);
    uint64_t controls = 0;
    assert(actql_native_owned_control_bytes(owner, &controls) == 0);
    assert(controls > 0 && controls < (uint64_t)page * 64);
    assert(actql_native_owned_leave(owner) == 0);
    assert(actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    printf("{\"profile\":\"linux-x64-posix-process\",\"passed\":1,"
           "\"page_bytes\":%ld,\"capacity_control_bytes\":%zu,"
           "\"capacity_alignment\":%zu,\"extent_bytes\":%zu,"
           "\"loan_bytes\":%zu,\"view_bytes\":%zu,\"thread_bytes\":%zu,"
           "\"thread_alignment\":%zu,\"int_bytes\":%zu,\"off_bytes\":%zu,"
           "\"pid_bytes\":%zu,\"pointer_bytes\":%zu,\"shared_pid_lock_free\":true}\n",
           page, sizeof(actql_owned_capacity), _Alignof(actql_owned_capacity),
           sizeof(struct extent), sizeof(actql_owned_extent_loan),
           sizeof(actql_owned_extent_view), actql_native_owned_thread_control_bytes(),
           actql_native_owned_thread_control_alignment(), sizeof(int), sizeof(off_t),
           sizeof(pid_t), sizeof(void *));
    return 0;
}
