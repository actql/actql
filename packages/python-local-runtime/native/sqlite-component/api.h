#ifndef ACTQL_PRIVATE_SQLITE_COMPONENT_API_H
#define ACTQL_PRIVATE_SQLITE_COMPONENT_API_H
#include "component.h"
#include <stdint.h>
#include <sqlite3.h>

/* Private in-process table, never DATA or authority. The original Library
 * owns one borrow until its last Database object and adapter buffer retire.
 * The caller holds the SAME original current scope around the whole call,
 * including managed argument/result conversion. No table field grants use. */
struct actql_sqlite_component_api {
    uint32_t abi;
    uint32_t bytes;
    const void *instance;
    void *(*allocate_memory)(size_t);
    const char *(*libversion)(void);
    int (*libversion_number)(void);
    int (*open_v2)(const char *, sqlite3 **, int, const char *);
    int (*close_v2)(sqlite3 *);
    const char *(*errmsg)(sqlite3 *);
    int (*exec)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    void (*free_memory)(void *);
    int (*prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    int (*bind_text)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
    int (*bind_blob)(sqlite3_stmt *, int, const void *, int, void (*)(void *));
    int (*bind_int64)(sqlite3_stmt *, int, sqlite3_int64);
    int (*step)(sqlite3_stmt *);
    sqlite3_int64 (*column_int64)(sqlite3_stmt *, int);
    const void *(*column_blob)(sqlite3_stmt *, int);
    int (*column_bytes)(sqlite3_stmt *, int);
    int (*finalize)(sqlite3_stmt *);
    sqlite3_int64 (*changes64)(sqlite3 *);
    int (*busy_timeout)(sqlite3 *, int);
    int (*get_autocommit)(sqlite3 *);
    int (*reset)(sqlite3_stmt *);
    int (*clear_bindings)(sqlite3_stmt *);
};
#define ACTQL_SQLITE_COMPONENT_ABI 3
#define ACTQL_SQLITE_COMPONENT_SOURCE_ID \
    "2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b"
#endif
