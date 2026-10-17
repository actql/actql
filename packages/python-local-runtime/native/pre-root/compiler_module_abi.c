/* Same original Core ABI declaration projection as the Python consumer.
 * C-API objects/arrays remain opaque and borrowed through official accessors;
 * no private Rust/MoonBit object layout, fresh Root or authority is introduced. */
#include "compiler_module_abi.h"
#include "compiler_core_abi.generated.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

static bool name_equal(const wasm_name_t *name, const char *expected) {
    size_t bytes = strlen(expected);
    return name != NULL && name->size == bytes &&
        (bytes == 0 || (name->data != NULL && memcmp(name->data, expected, bytes) == 0));
}

static bool kinds_equal(const wasm_valtype_vec_t *types, const char *expected) {
    size_t count = 0;
    for (const char *p = expected; *p != '\0';) {
        wasm_valkind_t kind;
        if (strncmp(p, "i32", 3) == 0) kind = WASM_I32;
        else if (strncmp(p, "i64", 3) == 0) kind = WASM_I64;
        else return false;
        if (types == NULL || count >= types->size || types->data == NULL ||
            types->data[count] == NULL || wasm_valtype_kind(types->data[count]) != kind)
            return false;
        count++;
        p += 3;
        if (*p == '\0') break;
        if (*p != ' ' || p[1] == '\0') return false;
        p++;
    }
    return types != NULL && count == types->size;
}

static bool function_equal(const wasm_externtype_t *type,
                           const actql_compiler_signature *expected) {
    if (type == NULL || wasm_externtype_kind(type) != WASM_EXTERN_FUNC) return false;
    const wasm_functype_t *function = wasm_externtype_as_functype_const(type);
    return function != NULL && kinds_equal(wasm_functype_params(function), expected->parameters) &&
        kinds_equal(wasm_functype_results(function), expected->result);
}

int actql_compiler_check_module_types(const wasm_importtype_vec_t *imports,
                                     const wasm_exporttype_vec_t *exports) {
    if (imports == NULL || imports->size != ACTQL_COMPILER_IMPORTS_COUNT ||
        (imports->size != 0 && imports->data == NULL)) return ACTQL_COMPILER_ABI_IMPORTS;
    bool imports_seen[ACTQL_COMPILER_IMPORTS_COUNT] = {false};
    for (size_t i = 0; i < imports->size; i++) {
        const wasm_importtype_t *item = imports->data[i];
        if (item == NULL || !name_equal(wasm_importtype_module(item), "actql_host"))
            return ACTQL_COMPILER_ABI_IMPORTS;
        bool found = false;
        for (size_t n = 0; n < ACTQL_COMPILER_IMPORTS_COUNT; n++) {
            if (!name_equal(wasm_importtype_name(item), actql_compiler_imports[n].name)) continue;
            if (imports_seen[n] || !function_equal(wasm_importtype_type(item), &actql_compiler_imports[n]))
                return ACTQL_COMPILER_ABI_IMPORTS;
            imports_seen[n] = true;
            found = true;
            break;
        }
        if (!found) return ACTQL_COMPILER_ABI_IMPORTS;
    }
    if (exports == NULL || exports->size != ACTQL_COMPILER_EXPORTS_COUNT + 1 ||
        exports->data == NULL) return ACTQL_COMPILER_ABI_EXPORTS;
    bool exports_seen[ACTQL_COMPILER_EXPORTS_COUNT] = {false};
    bool memory_seen = false;
    for (size_t i = 0; i < exports->size; i++) {
        const wasm_exporttype_t *item = exports->data[i];
        if (item == NULL) return ACTQL_COMPILER_ABI_EXPORTS;
        const wasm_externtype_t *type = wasm_exporttype_type(item);
        if (name_equal(wasm_exporttype_name(item), "memory")) {
            if (memory_seen || type == NULL || wasm_externtype_kind(type) != WASM_EXTERN_MEMORY)
                return ACTQL_COMPILER_ABI_MEMORY;
            const wasm_memorytype_t *memory = wasm_externtype_as_memorytype_const(type);
            uint64_t maximum = 0;
            if (memory == NULL || wasmtime_memorytype_is64(memory) || wasmtime_memorytype_isshared(memory) ||
                wasmtime_memorytype_minimum(memory) > 256 ||
                !wasmtime_memorytype_maximum(memory, &maximum) || maximum != 256)
                return ACTQL_COMPILER_ABI_MEMORY;
            memory_seen = true;
            continue;
        }
        bool found = false;
        for (size_t n = 0; n < ACTQL_COMPILER_EXPORTS_COUNT; n++) {
            if (!name_equal(wasm_exporttype_name(item), actql_compiler_exports[n].name)) continue;
            if (exports_seen[n] || !function_equal(type, &actql_compiler_exports[n]))
                return ACTQL_COMPILER_ABI_EXPORTS;
            exports_seen[n] = true;
            found = true;
            break;
        }
        if (!found) return ACTQL_COMPILER_ABI_EXPORTS;
    }
    return memory_seen ? ACTQL_COMPILER_ABI_MATCH : ACTQL_COMPILER_ABI_MEMORY;
}

int actql_compiler_check_module_abi(const wasmtime_module_t *module) {
    if (module == NULL) return ACTQL_COMPILER_ABI_IMPORTS;
    wasm_importtype_vec_t imports = {0};
    wasm_exporttype_vec_t exports = {0};
    wasmtime_module_imports(module, &imports);
    wasmtime_module_exports(module, &exports);
    int result = actql_compiler_check_module_types(&imports, &exports);
    wasm_exporttype_vec_delete(&exports);
    wasm_importtype_vec_delete(&imports);
    return result;
}
