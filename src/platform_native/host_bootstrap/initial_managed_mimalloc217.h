#ifndef ACTQL_INITIAL_MANAGED_MIMALLOC217_H
#define ACTQL_INITIAL_MANAGED_MIMALLOC217_H
#include <stdbool.h>
#include <stddef.h>

/* Selected public mimalloc 2.1.7 ABI (include/mimalloc.h, upstream v2.1.7).
 * The existing toolchain/entry recipe pins the actual runtime object; checking
 * mi_version alone never proves that correspondence. Keep this small private
 * import in one place, rather than installing or selecting another allocator. */
typedef struct mi_heap_s mi_heap_t;
extern int mi_version(void);
extern void mi_process_init(void);
extern void *mi_arena_area(int, size_t *);
extern mi_heap_t *mi_heap_new_in_arena(int);
extern mi_heap_t *mi_heap_set_default(mi_heap_t *);
extern mi_heap_t *mi_heap_get_default(void);
extern size_t mi_usable_size(const void *);
extern bool mi_manage_os_memory_ex(void *, size_t, bool, bool, bool, int, bool, int *);
/* The exact selected option indices are checked against the pinned object;
 * enum arguments use its public C int ABI. No generic option port is exposed. */
extern long mi_option_get(int);
extern void mi_option_set(int, long);

#endif
