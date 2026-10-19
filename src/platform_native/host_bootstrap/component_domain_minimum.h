#ifndef ACTQL_NATIVE_COMPONENT_DOMAIN_MINIMUM_H
#define ACTQL_NATIVE_COMPONENT_DOMAIN_MINIMUM_H
#include <stddef.h>
#include <stdint.h>

/* Necessary coexistence only, calculated by the SAME compiled provider's
 * control/context/slab layout and the caller's actual receiver payload sizes.
 * No allocation, original, reservation or full-input demand proof is issued.
 * Missing selected layout or invalid/overflowing inputs returns -1. */
int64_t actql_bootstrap_component_domain_necessary_bytes(
    int64_t domain_bytes, int64_t heap_bytes, size_t library_payload,
    size_t database_payload, size_t maximum_path_bytes);
int64_t actql_bootstrap_command_backing_control_necessary_bytes(int64_t bytes);
/* Same compiled control/context geometry for a managed execution domain.
 * payload is the caller's independently derived live allocation allowance;
 * this minimum adds no per-object demand proof or unused-capacity credit. */
int64_t actql_bootstrap_execution_domain_necessary_bytes(
    int64_t domain_bytes, int64_t payload_bytes);
#endif
