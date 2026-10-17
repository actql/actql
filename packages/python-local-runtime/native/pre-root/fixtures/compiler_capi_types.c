/* Actual selected C-API type objects on the original inherited Native domain.
 * Trusted parent preparation must retain its original child/frame/region and
 * fund this separate control storage before launch. Arguments are DATA only;
 * FD4 is the same captured original, never a reason to acquire another root. */
#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "owned_domain_borrow.h"
#include "compiler_module_abi.h"
#include "compiler_core_abi.generated.h"

static size_t arity(const char *types) {
    if (*types == '\0') return 0;
    size_t count = 1;
    for (const char *p = types; *p != '\0'; p++) if (*p == ' ') count++;
    return count;
}
static wasm_externtype_t *function(const actql_compiler_signature *signature, bool wrong) {
    wasm_valtype_vec_t parameters = {0}, results = {0};
    wasm_valtype_vec_new_uninitialized(&parameters, arity(signature->parameters));
    wasm_valtype_vec_new_uninitialized(&results, 1);
    const char *p = signature->parameters;
    for (size_t i = 0; i < parameters.size; i++, p += 4) {
        parameters.data[i] = wasm_valtype_new(wrong && i == 0 ? WASM_F32 :
            (strncmp(p, "i64", 3) == 0 ? WASM_I64 : WASM_I32));
        assert(parameters.data[i] != NULL);
    }
    results.data[0] = wasm_valtype_new(strcmp(signature->result, "i64") == 0 ? WASM_I64 : WASM_I32);
    assert(results.data[0] != NULL);
    wasm_functype_t *result = wasm_functype_new(&parameters, &results);
    assert(result != NULL);
    /* The C API takes the original vectors and function ownership; no copied
     * alias is subsequently destroyed by this caller. */
    return wasm_functype_as_externtype(result);
}

static void types(int variant, wasm_importtype_vec_t *imports, wasm_exporttype_vec_t *exports) {
    wasm_importtype_vec_new_uninitialized(imports, ACTQL_COMPILER_IMPORTS_COUNT);
    for (size_t i = 0; i < imports->size; i++) {
        wasm_name_t module = {0}, name = {0};
        wasm_name_new_from_string(&module, variant == 3 && i == 0 ? "foreign_host" : "actql_host");
        wasm_name_new_from_string(&name, actql_compiler_imports[variant == 4 && i == 1 ? 0 : i].name);
        imports->data[i] = wasm_importtype_new(&module, &name,
            function(&actql_compiler_imports[i], variant == 2 && i == 0));
        assert(imports->data[i] != NULL);
    }
    wasm_exporttype_vec_new_uninitialized(exports, ACTQL_COMPILER_EXPORTS_COUNT + 1);
    for (size_t i = 0; i < ACTQL_COMPILER_EXPORTS_COUNT; i++) {
        wasm_name_t name = {0};
        const char *selected = variant == 6 && i == 0 ? "future_export" :
            actql_compiler_exports[variant == 12 && i == 1 ? 0 : i].name;
        wasm_name_new_from_string(&name, selected);
        exports->data[i] = wasm_exporttype_new(&name, function(&actql_compiler_exports[i], false));
        assert(exports->data[i] != NULL);
    }
    wasm_name_t name = {0};
    wasm_name_new_from_string(&name, variant == 11 ? "other_memory" : "memory");
    wasm_memorytype_t *memory = wasmtime_memorytype_new(1, variant != 9,
        variant == 10 ? 257 : 256, variant == 7, variant == 8);
    assert(memory != NULL);
    exports->data[ACTQL_COMPILER_EXPORTS_COUNT] = wasm_exporttype_new(
        &name, wasm_memorytype_as_externtype(memory));
    assert(exports->data[ACTQL_COMPILER_EXPORTS_COUNT] != NULL);
}

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
    assert(actql_native_domain_borrow_open(record, bytes, 4, recipe, material) == 0);
    actql_owned_capacity *original = NULL;
    assert(actql_native_domain_borrow_claim_holding(record, &original) == 0);
    assert(actql_native_domain_borrow_transfer_holding(record, original, (uint64_t)material[0], recipe) == 0);
    assert(actql_native_domain_borrow_enter(record) == 0);
    int expected[] = {
        ACTQL_COMPILER_ABI_MATCH,
        ACTQL_COMPILER_ABI_IMPORTS, ACTQL_COMPILER_ABI_IMPORTS,
        ACTQL_COMPILER_ABI_IMPORTS, ACTQL_COMPILER_ABI_IMPORTS,
        ACTQL_COMPILER_ABI_EXPORTS, ACTQL_COMPILER_ABI_EXPORTS,
        ACTQL_COMPILER_ABI_MEMORY, ACTQL_COMPILER_ABI_MEMORY,
        ACTQL_COMPILER_ABI_MEMORY, ACTQL_COMPILER_ABI_MEMORY,
        ACTQL_COMPILER_ABI_EXPORTS, ACTQL_COMPILER_ABI_EXPORTS,
    };
    size_t total = sizeof(expected) / sizeof(expected[0]), passed = 0;
    for (size_t i = 0; i < total; i++) {
        wasm_importtype_vec_t imports = {0};
        wasm_exporttype_vec_t exports = {0};
        types((int)i, &imports, &exports);
        /* Narrow a borrowed view only for this invocation. Restore its exact
         * owning extent before the official destructor retires every member. */
        if (i == 1) imports.size--;
        if (i == 5) exports.size--;
        int result = actql_compiler_check_module_types(&imports, &exports);
        if (i == 1) imports.size++;
        if (i == 5) exports.size++;
        wasm_exporttype_vec_delete(&exports);
        wasm_importtype_vec_delete(&imports);
        if (result == expected[i]) passed++;
        else fprintf(stderr, "C-API type case %zu returned %d instead of %d\n", i + 1, result, expected[i]);
    }
    int leave = actql_native_domain_borrow_leave(record);
    int close = leave == 0 ? actql_native_domain_borrow_close_holding(record, &original) : ACTQL_OWNED_INVALID;
    /* A nonzero close is retained/unconfirmed, never a cleanup acknowledgment
     * manufactured from exit or a repeated acquire at a larger capacity. */
    printf("{\"discovered\":%zu,\"executed\":%zu,\"passed\":%zu,\"failed\":%zu,"
           "\"leave\":%d,\"holding_close\":%d,\"holding_closed\":%s,"
           "\"Engine\":0,\"Module\":0,\"VM\":0,\"normal_profile\":null}\n",
           total, total, passed, total - passed, leave, close, original == NULL ? "true" : "false");
    return passed == total && leave == 0 && close == 0 && original == NULL ? 0 : 1;
}
