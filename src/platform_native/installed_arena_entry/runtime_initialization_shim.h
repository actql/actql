#ifndef ACTQL_PRIVATE_RUNTIME_INITIALIZATION_SHIM_H
#define ACTQL_PRIVATE_RUNTIME_INITIALIZATION_SHIM_H
#include "control_shim.h"

/* One selected component's original process-lifetime initialization record.
 * Not a Host, Ledger, allocation receipt, supplier or physical retirement ACK.
 * The maintainer's existing initial control envelope owns this storage. */
typedef struct actql_control_runtime_origin actql_control_runtime_origin;

/* Publish the same static record before invoking this component's emitted
 * initializer. No second call, failure, reply loss or fork may reset it.
 * There is deliberately no close/free operation: arena/Engine/thread cleanup
 * does not retire this component's process-global Runtime responsibility. */
int actql_control_runtime_initialize_into(actql_control_runtime_origin **slot);
int actql_control_runtime_current(actql_control_runtime_origin *original);
#endif
