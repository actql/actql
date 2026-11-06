/* Same-provider original domain supplier. It never enters the parent TLS or
 * allocates a managed carrier. The root mapping owns every added receipt. */
enum owned_growth_state {
    OWNED_GROWTH_IDLE = 0, OWNED_GROWTH_QUOTED = 1,
    OWNED_GROWTH_ACQUIRING = 2, OWNED_GROWTH_ATTACHED = 3,
    OWNED_GROWTH_REFUSED = 4, OWNED_GROWTH_PARTIAL = 5,
    OWNED_GROWTH_CLOSED = 6
};
struct owned_growth_receipt {
    struct owned_growth_receipt *next;
    struct owned_segment *mapping;
    void *allocation;
    actql_owned_extent_loan loan;
    actql_owned_extent_view view;
    bool allocation_retired;
};

/* Exact solution of C*page >= header + (payload_pages+C)*extent_size.
 * No guessed growth chunk, fixed-point iteration cap or free-memory estimate. */
static bool domain_growth_layout(actql_owned_capacity *lease, size_t payload,
    size_t extra_control, size_t *total, size_t *control) {
    size_t pages;
    if (!round_pages(payload, lease->page_size, &pages) ||
        extra_control > SIZE_MAX - sizeof(struct owned_segment) ||
        lease->page_size <= sizeof(struct extent)) return false;
    size_t header = sizeof(struct owned_segment) + extra_control;
    if (pages > (SIZE_MAX - header) / sizeof(struct extent)) return false;
    size_t bytes = header + pages * sizeof(struct extent);
    size_t denominator = lease->page_size - sizeof(struct extent);
    size_t controls = bytes / denominator + (bytes % denominator != 0);
    if (controls > SIZE_MAX / lease->page_size ||
        pages > SIZE_MAX / lease->page_size - controls) return false;
    *control = controls * lease->page_size;
    *total = (pages + controls) * lease->page_size;
    return *total <= PTRDIFF_MAX;
}

static bool domain_growth_original_locked(actql_owned_capacity *domain) {
    struct owned_domain_growth *growth = &domain->growth;
    actql_owned_capacity *parent = growth->parent;
    return parent != NULL && parent != domain && !parent->fd_backed &&
        !parent->extent_domain && parent->transferred && !parent->closing &&
        !foreign_domain_process(parent) && !foreign_domain_process(domain) &&
        !domain->fd_backed && domain->extent_domain && domain->transferred &&
        !domain->closing && !domain->domain_borrow_attempted &&
        !domain->allocation_ceiling_attempted &&
        actql_native_owned_domain_matches_view(domain, growth->original_view,
                                               getpid()) == ACTQL_OWNED_OK &&
        whole_local_domain_view(growth->original_view, parent);
}

int actql_native_owned_prepare_domain_growth(actql_owned_capacity *domain,
    actql_owned_extent_view *original_view) {
    if (domain == NULL || original_view == NULL || original_view->original != original_view ||
        original_view->local_loan == NULL || current_capacity != NULL ||
        original_view->local_loan->owner == NULL || domain->growth.parent != NULL ||
        foreign_domain_process(domain)) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = original_view->local_loan->owner;
    if (parent == domain || foreign_domain_process(parent)) return ACTQL_OWNED_INVALID;
    lock_capacity(parent);
    lock_capacity(domain);
    int status = ACTQL_OWNED_INVALID;
    if (domain->active_scopes == 0 && domain->growth.parent == NULL &&
        parent->pending_growth_domain == NULL && !parent->allocation_ceiling_attempted) {
        domain->growth.parent = parent;
        domain->growth.original_view = original_view;
        if (domain_growth_original_locked(domain)) status = ACTQL_OWNED_OK;
        else {
            domain->growth.parent = NULL;
            domain->growth.original_view = NULL;
        }
    }
    unlock_capacity(domain);
    unlock_capacity(parent);
    return status;
}

int actql_native_owned_quote_domain_growth(actql_owned_capacity *domain,
    size_t contiguous_payload_bytes, uint64_t *serial) {
    if (domain == NULL || serial == NULL || *serial != 0 ||
        current_capacity != domain || current_process != getpid() ||
        domain->growth.parent == NULL) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = domain->growth.parent;
    if (foreign_domain_process(parent) || foreign_domain_process(domain)) return ACTQL_OWNED_BUSY;
    lock_capacity(parent);
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    size_t child_bytes, child_controls, root_bytes, root_controls;
    if (growth->state != OWNED_GROWTH_IDLE || growth->serial == INT64_MAX ||
        parent->pending_growth_domain != NULL || !domain_growth_original_locked(domain) ||
        !domain_growth_layout(domain, contiguous_payload_bytes, 0, &child_bytes, &child_controls) ||
        !domain_growth_layout(parent, child_bytes, sizeof(struct owned_growth_receipt),
                              &root_bytes, &root_controls) ||
        child_bytes > PTRDIFF_MAX - domain->length || root_bytes > PTRDIFF_MAX - parent->length)
        goto done;
    growth->expected_parent = parent->length;
    growth->expected_domain = domain->length;
    growth->parent_bytes = root_bytes;
    growth->parent_controls = root_controls;
    growth->domain_bytes = child_bytes;
    growth->domain_controls = child_controls;
    growth->state = OWNED_GROWTH_QUOTED;
    *serial = ++growth->serial;
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(domain);
    unlock_capacity(parent);
    return status;
}

int actql_native_owned_domain_growth_scalar(actql_owned_capacity *domain,
    uint64_t serial, unsigned field, uint64_t *out) {
    if (domain == NULL || out == NULL || *out != 0 || serial == 0 ||
        domain->growth.parent == NULL || foreign_domain_process(domain)) return ACTQL_OWNED_INVALID;
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    if (serial != growth->serial) goto done;
    switch (field) {
    case 0: *out = growth->state; break;
    case 1: *out = growth->expected_parent; break;
    case 2: *out = growth->expected_domain; break;
    case 3: *out = growth->parent_bytes; break;
    case 4: *out = growth->parent_controls; break;
    case 5: *out = growth->domain_bytes; break;
    case 6: *out = growth->domain_controls; break;
    default: goto done;
    }
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(domain);
    return status;
}

/* The trusted same Resource owner has admitted the entire quoted addition on
 * its existing reservation before calling. Fixed native calls cannot reenter
 * Common or construct payload between that decision and this operation. */
int actql_native_owned_acquire_domain_growth(actql_owned_capacity *domain,
    uint64_t serial) {
    if (domain == NULL || serial == 0 || current_capacity != domain ||
        current_process != getpid() || domain->growth.parent == NULL)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = domain->growth.parent;
    if (foreign_domain_process(parent) || foreign_domain_process(domain)) return ACTQL_OWNED_BUSY;
    lock_capacity(parent);
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    if (growth->serial != serial || growth->state != OWNED_GROWTH_QUOTED) goto done;
    /* Consume even a stale quote. Equal amounts never recreate its original
     * serial, and a refused/missing response cannot retry another acquisition. */
    growth->state = OWNED_GROWTH_REFUSED;
    if (!domain_growth_original_locked(domain) || parent->pending_growth_domain != NULL ||
        parent->length != growth->expected_parent || domain->length != growth->expected_domain)
        goto done;
    parent->pending_growth_domain = domain;
    growth->state = OWNED_GROWTH_ACQUIRING;
    uint64_t controls = 0;
    status = grow_capacity_locked(parent, growth->expected_parent, growth->parent_bytes,
                                  sizeof(struct owned_growth_receipt), &controls);
    if (status != ACTQL_OWNED_OK) {
        growth->state = OWNED_GROWTH_REFUSED;
        parent->pending_growth_domain = NULL;
        goto done;
    }
    /* Publication of this self-hosted receipt immediately follows mmap. No
     * fallible operation can lose the same newly acquired original mapping. */
    struct owned_segment *mapping = parent->segments;
    struct owned_growth_receipt *receipt = (void *)((unsigned char *)mapping +
        sizeof(*mapping) + mapping->page_count * sizeof(struct extent));
    memset(receipt, 0, sizeof(*receipt));
    receipt->mapping = mapping;
    receipt->next = growth->receipts;
    growth->receipts = growth->pending = receipt;
    growth->state = OWNED_GROWTH_PARTIAL;
    if (controls != growth->parent_controls) { status = ACTQL_OWNED_INVALID; goto done; }
    status = allocate_storage_original_locked(parent, growth->domain_bytes,
        parent->page_size, &receipt->allocation, true, domain);
    if (status != ACTQL_OWNED_OK) goto done;
    status = lend_extent_range_locked(parent, receipt->allocation, 0,
        growth->domain_bytes, true, &receipt->loan, true, true);
    if (status != ACTQL_OWNED_OK) goto done;
    status = view_in_process_extent_locked(&receipt->loan, 0, growth->domain_bytes,
                                           &receipt->view, true);
    if (status != ACTQL_OWNED_OK) goto done;
    controls = 0;
    status = attach_domain_segment_locked(domain, growth->original_view,
        &receipt->view, growth->expected_domain, &controls);
    if (status != ACTQL_OWNED_OK) goto done;
    if (controls != growth->domain_controls) { status = ACTQL_OWNED_INVALID; goto done; }
    growth->state = OWNED_GROWTH_ATTACHED;
done:
    unlock_capacity(domain);
    unlock_capacity(parent);
    return status;
}

int actql_native_owned_finish_domain_growth(actql_owned_capacity *domain,
    uint64_t serial) {
    if (domain == NULL || serial == 0 || current_capacity != domain ||
        current_process != getpid() || domain->growth.parent == NULL)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = domain->growth.parent;
    if (foreign_domain_process(parent) || foreign_domain_process(domain)) return ACTQL_OWNED_BUSY;
    lock_capacity(parent);
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    if (serial == growth->serial && growth->state == OWNED_GROWTH_ATTACHED &&
        parent->pending_growth_domain == domain && domain_growth_original_locked(domain) &&
        parent->length == growth->expected_parent + growth->parent_bytes &&
        domain->length == growth->expected_domain + growth->domain_bytes &&
        growth->pending != NULL && growth->pending->view.domain_live) {
        growth->state = OWNED_GROWTH_IDLE;
        growth->pending = NULL;
        parent->pending_growth_domain = NULL;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(domain);
    unlock_capacity(parent);
    return status;
}

/* A quote or atomic mmap refusal has acquired no new custody. This cannot
 * erase a partial/successful acquisition or acknowledge any physical cleanup. */
int actql_native_owned_cancel_domain_growth_quote(actql_owned_capacity *domain,
    uint64_t serial) {
    if (domain == NULL || serial == 0 || domain->growth.parent == NULL ||
        foreign_domain_process(domain)) return ACTQL_OWNED_INVALID;
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    if (serial == growth->serial && growth->pending == NULL &&
        (growth->state == OWNED_GROWTH_QUOTED || growth->state == OWNED_GROWTH_REFUSED)) {
        growth->state = OWNED_GROWTH_IDLE;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(domain);
    return status;
}

/* Only original domain close calls this, after all scopes/Read aliases/child
 * allocations retire and its views detach. Both original locks are held.
 * Keep each failed receipt and root mapping; cleanup is never inferred from
 * cancellation. Newly acquired root mappings remain until root's own close. */
static int cleanup_domain_growth_locked(actql_owned_capacity *domain) {
    struct owned_domain_growth *growth = &domain->growth;
    actql_owned_capacity *parent = growth->parent;
    if (parent == NULL) return ACTQL_OWNED_OK;
    while (growth->receipts != NULL) {
        struct owned_growth_receipt *receipt = growth->receipts;
        int status;
        if (receipt->view.original != NULL && receipt->view.mapping != NULL) {
            status = actql_native_owned_close_extent_view(&receipt->view);
            if (status != ACTQL_OWNED_OK) return status;
        }
        if (receipt->loan.original != NULL && !receipt->loan.returned) {
            status = return_extent_locked(&receipt->loan);
            if (status != ACTQL_OWNED_OK) return status;
        }
        if (receipt->allocation != NULL && !receipt->allocation_retired) {
            status = retire_allocation_locked(parent, receipt->allocation);
            if (status != ACTQL_OWNED_OK) return status;
            receipt->allocation_retired = true;
        }
        growth->receipts = receipt->next;
    }
    if (parent->pending_growth_domain == domain) parent->pending_growth_domain = NULL;
    growth->pending = NULL;
    growth->state = OWNED_GROWTH_CLOSED;
    return ACTQL_OWNED_OK;
}
