/* Actual selected C-API type objects on the original inherited Native domain.
 * Trusted parent preparation must retain its original child/frame/region and
 * fund this separate control storage before launch. Arguments are DATA only;
 * FD4 is the same captured original, never a reason to acquire another root. */
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "owned_domain_borrow.h"
#include "compiler_configuration.generated.h"

static int hex(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

int main(int argc, char **argv) {
    assert(argc == 17 && strlen(argv[1]) == 64);
    unsigned char recipe[32];
    for (size_t i = 0; i < 32; i++) {
        int high = hex((unsigned char)argv[1][2 * i]), low = hex((unsigned char)argv[1][2 * i + 1]);
        assert(high >= 0 && low >= 0);
        recipe[i] = (unsigned char)(16 * high + low);
    }
    int64_t material[15];
    for (size_t i = 0; i < 15; i++) {
        const char *value = argv[i + 2];
        assert(*value >= '0' && *value <= '9');
        char *end = NULL;
        errno = 0;
        intmax_t number = strtoimax(value, &end, 10);
        assert(errno == 0 && end != NULL && *end == '\0' && number >= 0 && number <= INT64_MAX);
        material[i] = (int64_t)number;
    }
    size_t bytes = actql_native_domain_borrow_storage_bytes();
    size_t alignment = actql_native_domain_borrow_storage_alignment();
    /* Existing bounded control-copy quantum, not an arena budget or grant.
     * Exact storage remains original and stable through partial map/close. */
    assert(bytes > 0 && bytes <= 65536 && alignment > 0 &&
           alignment <= _Alignof(max_align_t) && _Alignof(max_align_t) % alignment == 0);
    max_align_t record[(bytes + sizeof(max_align_t) - 1) / sizeof(max_align_t)];
    memset(record, 0, sizeof(record));
    /* The original parent confirms spawn/current and the same child binding
     * before this child maps FD4 or allocates any C-API object. EOF, a signal or
     * another byte is a refusal, never permission to bind ambient storage. */
    unsigned char ready = 0;
    ssize_t received;
    do { received = read(STDIN_FILENO, &ready, 1); }
    while (received < 0 && errno == EINTR);
    assert(received == 1 && ready == 'R');
    assert(actql_native_domain_borrow_open(record, bytes, 4, recipe, material) == 0);
    actql_owned_capacity *original = NULL;
    assert(actql_native_domain_borrow_claim_holding(record, &original) == 0);
    assert(actql_native_domain_borrow_transfer_holding(record, original, (uint64_t)material[0], recipe) == 0);
    assert(actql_native_domain_borrow_enter(record) == 0);
    /* Inspect the selected Runtime's actual dependency resolution. The Runtime
     * must use the same imported provider function as this original domain;
     * matching filenames or independently linked capacity copies do not pass. */
    void *runtime = dlopen("@rpath/_libwasmtime.dylib", RTLD_NOW | RTLD_NOLOAD);
    assert(runtime != NULL);
    void *provider_current = dlsym(runtime, "actql_native_owned_current");
    assert(provider_current != NULL &&
           provider_current == dlsym(RTLD_DEFAULT, "actql_native_owned_current"));
    assert(dlclose(runtime) == 0);
    size_t passed = 0;
    for (int candidate = 0; candidate < 2; candidate++) {
        wasm_config_t *config = wasm_config_new();
        assert(config != NULL);
        wasmtime_pooling_allocation_config_t *pool = wasmtime_pooling_allocation_config_new();
        assert(pool != NULL);
        wasmtime_error_t *error = candidate == 0 ? actql_compiler_configure(config, pool) :
            wasmtime_config_target_set(config, "not-an-actual-target");
        bool matched = candidate == 0 ? error == NULL : error != NULL;
        if (error != NULL) wasmtime_error_delete(error);
        /* Strategy attachment copies settings and does not take the pool.
         * Keep and destroy both original objects inside this original scope. */
        wasmtime_pooling_allocation_config_delete(pool);
        wasm_config_delete(config);
        if (matched) passed++;
    }
    int leave = actql_native_domain_borrow_leave(record);
    int close = leave == 0 ? actql_native_domain_borrow_close_holding(record, &original) : ACTQL_OWNED_INVALID;
    printf("{\"discovered\":2,\"executed\":2,\"passed\":%zu,\"failed\":%zu,"
           "\"leave\":%d,\"holding_close\":%d,\"holding_closed\":%s,"
           "\"same_provider_symbol\":true,\"Config\":2,\"Engine\":0,\"Module\":0,"
           "\"VM\":0,\"normal_profile\":null}\n",
           passed, 2 - passed, leave, close, original == NULL ? "true" : "false");
    return passed == 2 && leave == 0 && close == 0 && original == NULL ? 0 : 1;
}
