#ifndef ACTQL_PRIVATE_CONTROL_SHIM_H
#define ACTQL_PRIVATE_CONTROL_SHIM_H

#include "moonbit.h"
#include <stddef.h>
#include <stdint.h>

/* Opaque tags from actual Sourcea312 C emission, sha256 9a3bafc1b6d79b70
 * c622d5f2f34685998d9427e7e7c3f02da472de027ceb063a. Never inspect fields. */
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control18InstalledArenaHost actql_control_host;
typedef struct _M0TP45actql5actql16platform__native25installed__arena__control19InstalledArenaReply actql_control_reply;

typedef actql_control_reply *(*actql_control_prepare_fn)(
    moonbit_string_t, moonbit_bytes_t, int64_t, int64_t,
    int32_t, int32_t, int32_t, int64_t, int64_t, int64_t, int64_t);
typedef actql_control_reply *(*actql_control_operation_fn)(actql_control_host *);
typedef actql_control_host *(*actql_control_original_fn)(actql_control_reply *);
typedef int32_t (*actql_control_tag_fn)(actql_control_reply *);
typedef moonbit_string_t (*actql_control_description_fn)(actql_control_reply *);

void actql_native_control_register_original_roots(
    actql_control_prepare_fn, actql_control_operation_fn,
    actql_control_operation_fn, actql_control_operation_fn,
    actql_control_original_fn, actql_control_tag_fn,
    actql_control_tag_fn, actql_control_description_fn);

/* Trusted in-process installed caller only: no wire pointers or authorization.
 * This exact generated callback set borrows managed inputs. Results are
 * caller-owned references; this is not a claim about other MoonBit exports.
 * Callers retain all original inputs throughout the call, including reentry. */
actql_control_reply *actql_control_prepare(
    moonbit_string_t, moonbit_bytes_t, int64_t, int64_t,
    int32_t, int32_t, int32_t, int64_t, int64_t, int64_t, int64_t);
actql_control_reply *actql_control_acquire(actql_control_host *);
actql_control_reply *actql_control_current(actql_control_host *);
actql_control_reply *actql_control_close(actql_control_host *);
actql_control_host *actql_control_original(actql_control_reply *);
int32_t actql_control_operation(actql_control_reply *);
int32_t actql_control_issue_family(actql_control_reply *);
moonbit_string_t actql_control_description(actql_control_reply *);
/* Persistent out-slots let the trusted foreign caller retain newly returned
 * references even when the call's response is lost. No slot may be overwritten.
 * originals_into returns two owned references to the same nominal Host. */
int actql_control_originals_into(actql_control_reply *,
                                actql_control_host **, actql_control_host **);
int actql_control_current_into(actql_control_host *, actql_control_reply **);

/* These private transport statuses are not Run, permission or publication
 * outcomes. Pending retains the same original slot and exact typed reply. */
enum {
    ACTQL_CONTROL_OK = 0,
    ACTQL_CONTROL_UNAVAILABLE = -1,
    ACTQL_CONTROL_INVALID_SLOT = -2,
    ACTQL_CONTROL_CLEANUP_PENDING = -3
};

/* Drop data only while its original Host is independently retained by caller.
 * No implicit close, acquisition, retry or direct physical-provider release. */
int actql_control_drop_reply(actql_control_reply **, actql_control_host *);
/* Close through the original Owner, then drop Host only after typed Close/Ok.
 * Failure keeps Host untouched and transfers the exact reply to the out-slot. */
int actql_control_try_close_and_drop(
    actql_control_host **, actql_control_reply **);

#endif
