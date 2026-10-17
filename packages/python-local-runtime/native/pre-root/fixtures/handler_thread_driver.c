/* Actual one-provider Rust/C leaf only. No Engine, normal funding or old Run. */
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../owned_capacity.h"

int main(int argc, char **argv) {
    assert(argc == 2);
    actql_owned_capacity *owner = NULL;
    unsigned char recipe[32] = {31};
    long page = sysconf(_SC_PAGESIZE); assert(page > 0);
    assert(actql_native_owned_acquire((size_t)page * 64, 1, recipe, &owner) == 0);
    assert(actql_native_owned_enter(owner) == 0);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) { fprintf(stderr, "%s\n", dlerror()); return 2; }
    void *symbol = dlsym(library, "actql_test_original_thread_case");
    int (*run)(int) = NULL; assert(sizeof(run) == sizeof(symbol)); memcpy(&run, &symbol, sizeof(run)); assert(run);
    symbol = dlsym(library, "actql_test_original_provider_current_address");
    void *(*address)(void) = NULL; assert(sizeof(address) == sizeof(symbol)); memcpy(&address, &symbol, sizeof(address));
    assert(address && address() == dlsym(RTLD_DEFAULT, "actql_native_owned_current"));
    for (int i = 0; i < 4; i++) {
        fprintf(stderr, "original mixed Rust/C case %d/4\n", i + 1);
        assert(run(i) == 0);
    }
    assert(actql_native_owned_leave(owner) == 0);
    /* The library/key stay loaded in this original process through its end.
     * Closing this original mapping is a separate actual observation. */
    assert(actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    puts("{\"discovered\":4,\"executed\":4,\"passed\":4,\"failed\":0,\"fixture_pages\":64,\"original_closed\":true,\"Engine\":0,\"VM\":0}");
    return 0;
}
