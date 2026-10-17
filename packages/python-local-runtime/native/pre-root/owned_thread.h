#ifndef ACTQL_OWNED_THREAD_H
#define ACTQL_OWNED_THREAD_H
#include "owned_capacity.h"

/* Private physical thread adapter. Storage and callback/data aliases belong to
 * the original caller and remain live through confirmed join. These operations
 * do not issue a Core grant, fund an OS thread/stack or choose another holding. */
typedef void (*actql_owned_thread_entry)(void *argument);
size_t actql_native_owned_thread_control_bytes(void);
size_t actql_native_owned_thread_control_alignment(void);
/* Requires zeroed, aligned storage within one LIVE allocation of this current
 * original lease. Pins that lease BEFORE pthread_create. The C trampoline binds
 * its existing TLS before callback/Rust bootstrap and retains it through TSD
 * destructors. Startup refusal is one-shot, not permission to reuse the record. */
int actql_native_owned_thread_start(actql_owned_capacity *lease, void *storage,
    size_t storage_bytes, actql_owned_thread_entry entry, void *argument);
/* The selected Rust backend supplies its original initialized pthread attributes.
 * Borrowed only during this synchronous call; this port does not mint stack
 * funding or choose another attribute/default policy. No ambient interposition. */
int actql_native_owned_thread_start_configured(actql_owned_capacity *lease,
    void *storage, size_t storage_bytes, const void *attributes,
    actql_owned_thread_entry entry, void *argument);
/* A known no-start or successful pthread_join confirms stop and retires the
 * original scope pin. A child-binding failure still requires this same join. Callback return, cancellation request or PID observations do not. Storage
 * remains caller-owned, including after join. A lost/failed join is sticky and
 * never repeated; copying, forking or retiring the record gives no authority. */
int actql_native_owned_thread_join(actql_owned_capacity *lease, void *storage);
#endif
