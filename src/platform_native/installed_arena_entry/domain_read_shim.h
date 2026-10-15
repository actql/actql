#ifndef ACTQL_PRIVATE_DOMAIN_READ_SHIM_H
#define ACTQL_PRIVATE_DOMAIN_READ_SHIM_H
#include "domain_shim.h"
/* Actual Source7d6df1e6 regular C SHA256 b50d84954b4085485e022c0c94bcbee4
 * 06759c2f559d3c00e7ccdcd34b75931c: six same Host/domain callbacks, borrowed
 * inputs and owned original domain replies. No generated layout inspection. */
void actql_native_control_register_domain_read_roots(
    actql_domain_operation_fn, actql_domain_operation_fn,
    actql_domain_operation_fn, actql_domain_operation_fn,
    actql_domain_operation_fn, actql_domain_operation_fn);
/* Persistent original reply slots; caller must use existing typed operation,
 * issue, original getters and drop functions. Transport zero is not an ACK. */
int actql_domain_read_prepare_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_read_current_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_read_enter_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_read_leave_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_read_cleanup_into(actql_control_host *, actql_domain *, actql_domain_reply **);
int actql_domain_read_close_into(actql_control_host *, actql_domain *, actql_domain_reply **);
#endif
