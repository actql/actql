#ifndef ACTQL_PRIVATE_SQLITE_COMPONENT_H
#define ACTQL_PRIVATE_SQLITE_COMPONENT_H
#include <stddef.h>

/* Source candidate only. The installed Library Owner must supply its original
 * current Host/domain; an address, recipe or successful call grants no authority. */
typedef struct actql_read_context actql_read_context;
typedef struct actql_sqlite_component_api actql_sqlite_component_api;
enum actql_sqlite_component_status {
    ACTQL_SQLITE_COMPONENT_OK = 0,
    ACTQL_SQLITE_COMPONENT_INVALID = -1,
    ACTQL_SQLITE_COMPONENT_BUSY = -2,
    ACTQL_SQLITE_COMPONENT_FAILED = -3
};
int actql_sqlite_component_bind(actql_read_context *original, size_t heap_bytes);
/* Adapter text/diagnostic/result buffers use these SAME engine memory methods.
 * They are private physical operations, not an installed allocation supplier. */
void *actql_sqlite_component_allocate(size_t bytes);
void *actql_sqlite_component_resize(void *original, size_t bytes);
size_t actql_sqlite_component_size(void *original);
int actql_sqlite_component_free(void *original);
/* Refuses outstanding engine/adapter buffers. Releases only this Library's
 * retained context user; the original domain Owner still confirms retirement. */
int actql_sqlite_component_close(void);
/* Observation of this original connection after its first WAL access. This
 * neither selects locking mode nor supplies a Journal claim or heap capacity. */
int actql_sqlite_component_heap_wal(void *database);
/* A failed one-shot original VFS descriptor close stays with this component.
 * This observation cannot reclose it or release any parent responsibility. */
int actql_sqlite_component_descriptor_ack(void *unused);
/* Selected owned read-only inspection copy: no shared-memory mappings may
 * substitute for the private recovery index. The copy Owner retains its
 * unique empty SHM and original source/copy cleanup separately. */
int actql_sqlite_component_readonly_heap_wal(void *database);
const char *actql_sqlite_component_source_id(void);
/* One Library borrow, refused before initialization or after close. The table
 * contains no Host permission and cannot be persisted/reconstructed on reopen. */
const actql_sqlite_component_api *actql_sqlite_component_borrow_api(void);
int actql_sqlite_component_release_api(const actql_sqlite_component_api *original);
#endif
