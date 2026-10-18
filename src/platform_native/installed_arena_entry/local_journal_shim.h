#ifndef ACTQL_PRIVATE_LOCAL_JOURNAL_SHIM_H
#define ACTQL_PRIVATE_LOCAL_JOURNAL_SHIM_H
#include <stdint.h>
#include <moonbit.h>
/* Opaque same-provider managed objects, never integer handles or layouts. */
typedef void actql_local_session;
typedef void actql_local_host;
typedef void actql_local_journal_failure;
typedef void actql_local_journal_capture;
typedef void actql_local_journal_reply;
typedef void actql_local_sqlite_library;
typedef void actql_local_crypto_library;

typedef actql_local_journal_capture *(*actql_local_journal_prepare_fn)(
    actql_local_session *, actql_local_sqlite_library *, actql_local_crypto_library *,
    double, int32_t, int64_t);
typedef actql_local_journal_reply *(*actql_local_journal_operation_fn)(actql_local_journal_capture *);
typedef actql_local_journal_capture *(*actql_local_journal_capture_fn)(actql_local_journal_reply *);
typedef actql_local_session *(*actql_local_journal_session_fn)(actql_local_journal_capture *);
typedef actql_local_host *(*actql_local_journal_host_fn)(actql_local_journal_capture *);
typedef actql_local_journal_failure *(*actql_local_journal_failure_fn)(actql_local_journal_capture *);
typedef int32_t (*actql_local_journal_capture_tag_fn)(actql_local_journal_capture *);
typedef int32_t (*actql_local_journal_reply_tag_fn)(actql_local_journal_reply *);
#endif
