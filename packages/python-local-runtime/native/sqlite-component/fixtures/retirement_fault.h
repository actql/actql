/* Fixture-only fault at the original provider's physical syscall boundary.
 * No replacement provider, Ledger or production allocator is linked here. */
#include <errno.h>
#include <sys/mman.h>
static int retirement_fault_armed;
static unsigned retirement_calls;
static int retirement_mprotect(void *address, size_t bytes, int protection) {
    if (protection == PROT_NONE && bytes == 32 * (size_t)sysconf(_SC_PAGESIZE)) {
        retirement_calls++;
        if (retirement_fault_armed) {
            retirement_fault_armed = 0;
            errno = EIO;
            return -1;
        }
    }
    return mprotect(address, bytes, protection);
}
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; }
retirement_interpose = {(const void *)retirement_mprotect, (const void *)mprotect};
