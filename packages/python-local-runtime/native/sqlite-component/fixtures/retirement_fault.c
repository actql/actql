/* Fixture-only fault at the original provider's physical syscall boundary.
 * No replacement provider, Ledger or production allocator is linked here. */
#include <errno.h>
#include <unistd.h>
#include <sys/mman.h>
static int retirement_fault_armed;
static unsigned retirement_calls;
void actql_fixture_retirement_arm(void) { retirement_fault_armed = 1; }
unsigned actql_fixture_retirement_calls(void) { return retirement_calls; }
int actql_fixture_retirement_armed(void) { return retirement_fault_armed; }
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
