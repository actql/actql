#ifndef ACTQL_PRIVATE_SQLITE_COMPONENT_H
#define ACTQL_PRIVATE_SQLITE_COMPONENT_H
#include <stddef.h>

/* Source candidate only. The installed Library Owner must supply its original
 * current Host/domain; an address, recipe or successful call grants no authority. */
typedef struct actql_read_context actql_read_context;
enum actql_sqlite_component_status {
    ACTQL_SQLITE_COMPONENT_OK = 0,
    ACTQL_SQLITE_COMPONENT_INVALID = -1,
    ACTQL_SQLITE_COMPONENT_BUSY = -2,
    ACTQL_SQLITE_COMPONENT_FAILED = -3
};
int actql_sqlite_component_bind(actql_read_context *original);
/* Adapter text/diagnostic/result buffers use these SAME engine memory methods.
 * They are private physical operations, not an installed allocation supplier. */
void *actql_sqlite_component_allocate(size_t bytes);
void *actql_sqlite_component_resize(void *original, size_t bytes);
size_t actql_sqlite_component_size(void *original);
int actql_sqlite_component_free(void *original);
/* Refuses outstanding engine/adapter buffers. Releases only this Library's
 * retained context user; the original domain Owner still confirms retirement. */
int actql_sqlite_component_close(void);
const char *actql_sqlite_component_source_id(void);
#endif
