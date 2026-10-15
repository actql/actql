#include "domain_read_shim.h"
/* Code roots only: the original Native domain owns every use, partial context
 * and cleanup decision. This table cannot manufacture current or permission. */
static struct {
    actql_domain_operation_fn prepare, current, enter, leave, cleanup, close;
} read_callbacks;
static int read_registered;
void actql_native_control_register_domain_read_roots(
    actql_domain_operation_fn prepare, actql_domain_operation_fn current,
    actql_domain_operation_fn enter, actql_domain_operation_fn leave,
    actql_domain_operation_fn cleanup, actql_domain_operation_fn close) {
    if (read_registered) return;
    if (!prepare || !current || !enter || !leave || !cleanup || !close) {
        read_registered = -1;
        return;
    }
    read_callbacks.prepare = prepare;
    read_callbacks.current = current;
    read_callbacks.enter = enter;
    read_callbacks.leave = leave;
    read_callbacks.cleanup = cleanup;
    read_callbacks.close = close;
    read_registered = 1;
}
static int read_operation_into(actql_domain_operation_fn operation,
    actql_control_host *host, actql_domain *domain, actql_domain_reply **reply) {
    if (!host || !domain || !reply || *reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (read_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *reply = operation(host, domain);
    return *reply ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
#define READ_OPERATION(NAME, FIELD) \
int NAME(actql_control_host *host, actql_domain *domain, actql_domain_reply **reply) { \
    return read_operation_into(read_callbacks.FIELD, host, domain, reply); \
}
READ_OPERATION(actql_domain_read_prepare_into, prepare)
READ_OPERATION(actql_domain_read_current_into, current)
READ_OPERATION(actql_domain_read_enter_into, enter)
READ_OPERATION(actql_domain_read_leave_into, leave)
READ_OPERATION(actql_domain_read_cleanup_into, cleanup)
READ_OPERATION(actql_domain_read_close_into, close)
#undef READ_OPERATION
