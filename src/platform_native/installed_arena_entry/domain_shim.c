#include "domain_shim.h"
#include <string.h>
static struct {
    actql_domain_prepare_fn prepare;
    actql_domain_operation_fn current, transfer, enter, leave, close;
    actql_domain_original_fn original;
    actql_domain_handle_fn domain;
    actql_domain_tag_fn operation, issue;
    actql_domain_description_fn description;
} domain_callbacks;
static int domain_registered;
void actql_native_control_register_domain_roots(
    actql_domain_prepare_fn prepare, actql_domain_operation_fn current,
    actql_domain_operation_fn transfer, actql_domain_operation_fn enter,
    actql_domain_operation_fn leave, actql_domain_operation_fn close,
    actql_domain_original_fn original, actql_domain_handle_fn domain,
    actql_domain_tag_fn operation, actql_domain_tag_fn issue,
    actql_domain_description_fn description) {
    if (domain_registered) return;
    if (!prepare || !current || !transfer || !enter || !leave || !close ||
        !original || !domain || !operation || !issue || !description) {
        domain_registered = -1;
        return;
    }
    domain_callbacks.prepare = prepare;
    domain_callbacks.current = current;
    domain_callbacks.transfer = transfer;
    domain_callbacks.enter = enter;
    domain_callbacks.leave = leave;
    domain_callbacks.close = close;
    domain_callbacks.original = original;
    domain_callbacks.domain = domain;
    domain_callbacks.operation = operation;
    domain_callbacks.issue = issue;
    domain_callbacks.description = description;
    domain_registered = 1;
}
int actql_domain_prepare_into(actql_control_host *host, actql_backing_loan *scope,
    int32_t fd, int64_t bytes, int32_t work, int32_t attempts, int32_t holdings,
    int64_t transfer, int64_t retained, int64_t execution, actql_domain_reply **slot) {
    if (!host || !scope || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = domain_callbacks.prepare(host, scope, fd, bytes, work, attempts, holdings,
                                     transfer, retained, execution);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
static int domain_operation_into(actql_domain_operation_fn operation,
    actql_control_host *host, actql_domain *domain, actql_domain_reply **slot) {
    if (!host || !domain || !slot || *slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *slot = operation(host, domain);
    return *slot ? ACTQL_CONTROL_OK : ACTQL_CONTROL_UNAVAILABLE;
}
#define DOMAIN_OPERATION(NAME, FIELD) \
int NAME(actql_control_host *host, actql_domain *domain, actql_domain_reply **slot) { \
    return domain_operation_into(domain_callbacks.FIELD, host, domain, slot); \
}
DOMAIN_OPERATION(actql_domain_current_into, current)
DOMAIN_OPERATION(actql_domain_transfer_into, transfer)
DOMAIN_OPERATION(actql_domain_enter_into, enter)
DOMAIN_OPERATION(actql_domain_leave_into, leave)
DOMAIN_OPERATION(actql_domain_close_into, close)
#undef DOMAIN_OPERATION
int actql_domain_originals_into(actql_domain_reply *reply,
    actql_control_host **host, actql_domain **domain) {
    if (!reply || !host || !domain || *host || *domain || (void *)host == (void *)domain)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    *host = domain_callbacks.original(reply);
    if (!*host) return ACTQL_CONTROL_UNAVAILABLE;
    *domain = domain_callbacks.domain(reply);
    return ACTQL_CONTROL_OK;
}
int32_t actql_domain_operation(actql_domain_reply *reply) {
    return domain_registered == 1 && reply ? domain_callbacks.operation(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
int32_t actql_domain_issue_family(actql_domain_reply *reply) {
    return domain_registered == 1 && reply ? domain_callbacks.issue(reply) : ACTQL_CONTROL_UNAVAILABLE;
}
static int same_domain_reply(actql_domain_reply *reply,
    actql_control_host *retained_host, actql_domain *retained_domain) {
    actql_control_host *host = domain_callbacks.original(reply);
    actql_domain *domain = domain_callbacks.domain(reply);
    int same = host && host == retained_host && domain == retained_domain;
    if (domain) moonbit_decref(domain);
    if (host) moonbit_decref(host);
    return same;
}
int actql_domain_drop_reply(actql_domain_reply **slot,
    actql_control_host *host, actql_domain *domain) {
    if (!slot) return ACTQL_CONTROL_INVALID_SLOT;
    if (!*slot) return ACTQL_CONTROL_OK;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!host || !same_domain_reply(*slot, host, domain)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_domain_reply *owned = *slot;
    *slot = NULL;
    moonbit_decref(owned);
    return ACTQL_CONTROL_OK;
}
int actql_domain_finish_closed_data(actql_control_host **host,
    actql_domain **domain, actql_domain_reply **reply) {
    if (!host || !domain || !reply || !*host || !*domain || !*reply ||
        (void *)host == (void *)domain || (void *)host == (void *)reply ||
        (void *)domain == (void *)reply) return ACTQL_CONTROL_INVALID_SLOT;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (domain_callbacks.operation(*reply) != 6 || domain_callbacks.issue(*reply) != 0 ||
        !same_domain_reply(*reply, *host, *domain)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_domain_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_domain *d = *domain; *domain = NULL; moonbit_decref(d);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}
int actql_domain_finish_refused_prepare(actql_control_host **host, actql_domain_reply **reply) {
    if (!host || !reply || !*host || !*reply || (void *)host == (void *)reply)
        return ACTQL_CONTROL_INVALID_SLOT;
    if (domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (domain_callbacks.operation(*reply) != 1 || domain_callbacks.issue(*reply) == 0 ||
        !same_domain_reply(*reply, *host, NULL)) return ACTQL_CONTROL_INVALID_SLOT;
    actql_domain_reply *r = *reply; *reply = NULL; moonbit_decref(r);
    actql_control_host *h = *host; *host = NULL; moonbit_decref(h);
    return ACTQL_CONTROL_OK;
}

static struct {
    actql_domain_operation_fn project;
    actql_domain_scalar_fn scalar;
    actql_domain_description_fn source;
    actql_domain_recipe_fn recipe;
} material_callbacks;
static int material_registered;
void actql_native_control_register_domain_material_roots(
    actql_domain_operation_fn project, actql_domain_scalar_fn scalar,
    actql_domain_description_fn source, actql_domain_recipe_fn recipe) {
    if (material_registered) return;
    if (!project || !scalar || !source || !recipe) { material_registered = -1; return; }
    material_callbacks.project = project;
    material_callbacks.scalar = scalar;
    material_callbacks.source = source;
    material_callbacks.recipe = recipe;
    material_registered = 1;
}
int actql_domain_project_into(actql_control_host *host, actql_domain *domain,
                              actql_domain_reply **slot) {
    if (material_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    return domain_operation_into(material_callbacks.project, host, domain, slot);
}
int actql_domain_copy_material(actql_domain_reply *reply, actql_control_host *host,
    actql_domain *domain, unsigned char source[40], unsigned char recipe[32], int64_t scalars[15]) {
    if (material_registered != 1 || domain_registered != 1) return ACTQL_CONTROL_UNAVAILABLE;
    if (!reply || !host || !domain || !source || !recipe || !scalars ||
        domain_callbacks.operation(reply) != 7 || domain_callbacks.issue(reply) != 0 ||
        !same_domain_reply(reply, host, domain)) return ACTQL_CONTROL_INVALID_SLOT;
    moonbit_string_t text = material_callbacks.source(reply);
    moonbit_bytes_t bytes = material_callbacks.recipe(reply);
    int status = ACTQL_CONTROL_INVALID_SLOT;
    if (!text || !bytes || Moonbit_array_length(text) != 40 || Moonbit_array_length(bytes) != 32)
        goto done;
    /* Core source identity is ASCII hex. Reject non-ASCII rather than truncate
     * UTF-16 units or interpret String.to_bytes as UTF-8. */
    for (size_t i = 0; i < 40; i++) {
        if (!((text[i] >= '0' && text[i] <= '9') || (text[i] >= 'a' && text[i] <= 'f')))
            goto done;
        source[i] = (unsigned char)text[i];
    }
    memcpy(recipe, bytes, 32);
    for (int32_t i = 0; i < 15; i++) scalars[i] = material_callbacks.scalar(reply, i);
    status = ACTQL_CONTROL_OK;
done:
    if (bytes) moonbit_decref(bytes);
    if (text) moonbit_decref(text);
    return status;
}
