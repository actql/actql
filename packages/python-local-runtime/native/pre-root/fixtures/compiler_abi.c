/* Independent literal checks of the original scalar ABI projection. These
 * exercise a generated declaration table, not Module/Engine execution. */
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "compiler_core_abi.generated.h"

static const actql_compiler_signature *find(const actql_compiler_signature *items,
                                           size_t count, const char *name) {
    for (size_t i = 0; i < count; i++) if (strcmp(items[i].name, name) == 0) return &items[i];
    return NULL;
}
static bool signature(const actql_compiler_signature *item, const char *parameters,
                      const char *result) {
    return item != NULL && strcmp(item->parameters, parameters) == 0 && strcmp(item->result, result) == 0;
}
int main(void) {
    bool cases[] = {
        ACTQL_COMPILER_CORE_ABI == 86,
        ACTQL_COMPILER_IMPORTS_COUNT == 28,
        signature(find(actql_compiler_imports, ACTQL_COMPILER_IMPORTS_COUNT, "input_byte"),
                  "i32 i32", "i32"),
        signature(find(actql_compiler_imports, ACTQL_COMPILER_IMPORTS_COUNT, "execution_child_report"),
                  "i64 i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i32 i32 i32", "i32"),
        signature(find(actql_compiler_exports, ACTQL_COMPILER_EXPORTS_COUNT, "actql_buffer_open_live"),
                  "i64 i64 i32 i32", "i32"),
        find(actql_compiler_exports, ACTQL_COMPILER_EXPORTS_COUNT, "actql_buffer_open_fake") == NULL,
        signature(find(actql_compiler_exports, ACTQL_COMPILER_EXPORTS_COUNT, "actql_host_abi_version"),
                  "", "i32"),
        signature(find(actql_compiler_imports, ACTQL_COMPILER_IMPORTS_COUNT, "execution_child_capacity"),
                  "i64 i32", "i64"),
        signature(find(actql_compiler_imports, ACTQL_COMPILER_IMPORTS_COUNT, "platform_vm_observation"),
                  "i64 i32", "i64"),
        signature(find(actql_compiler_exports, ACTQL_COMPILER_EXPORTS_COUNT, "actql_buffer_open_platform"),
                  "i64 i64 i32 i32 i32 i32 i32 i64 i64 i64 i64", "i32"),
    };
    size_t total = sizeof(cases) / sizeof(cases[0]), passed = 0;
    for (size_t i = 0; i < total; i++) {
        if (cases[i]) passed++;
        else fprintf(stderr, "independent compiler ABI literal case %zu failed\n", i + 1);
    }
    printf("{\"discovered\":%zu,\"executed\":%zu,\"passed\":%zu,\"failed\":%zu,"
           "\"skipped\":0,\"Engine\":0,\"module_execution\":0}\n", total, total, passed, total - passed);
    return passed == total ? 0 : 1;
}
