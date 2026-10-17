#ifndef ACTQL_COMPILER_MODULE_ABI_H
#define ACTQL_COMPILER_MODULE_ABI_H

#include <wasmtime/module.h>
#include <wasmtime/memory.h>

/* Shape observations only. The trusted caller must already hold the original
 * same-provider scope before any C-API allocation or these inspections. This
 * does not instantiate Wasm, call its ABI version function or issue funding. */
enum actql_compiler_abi_observation {
    ACTQL_COMPILER_ABI_MATCH = 0,
    ACTQL_COMPILER_ABI_IMPORTS = 1,
    ACTQL_COMPILER_ABI_EXPORTS = 2,
    ACTQL_COMPILER_ABI_MEMORY = 3
};

int actql_compiler_check_module_abi(const wasmtime_module_t *module);

/* Borrowed C-API vectors from that same module. Kept separate to exercise
 * independent actual C-API type vectors without constructing an Engine. */
int actql_compiler_check_module_types(const wasm_importtype_vec_t *imports,
                                     const wasm_exporttype_vec_t *exports);
#endif
