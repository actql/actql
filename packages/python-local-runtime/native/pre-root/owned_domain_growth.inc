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

/* Retirement uses identity without reopening either closing original. */
static bool domain_growth_identity_locked(actql_owned_capacity *domain) {
    struct owned_domain_growth *growth = &domain->growth;
    actql_owned_capacity *parent = growth->parent;
    return parent != NULL && parent != domain && !parent->fd_backed &&
        !parent->extent_domain && parent->transferred &&
        !foreign_domain_process(parent) && !foreign_domain_process(domain) &&
        !domain->fd_backed && domain->extent_domain && domain->transferred &&
        atomic_load_explicit(&domain->domain_borrower_pid, memory_order_acquire) == 0 &&
        actql_native_owned_domain_matches_view(domain, growth->original_view,
                                               getpid()) == ACTQL_OWNED_OK &&
        whole_local_domain_view(growth->original_view, parent);
}

static bool domain_growth_original_locked(actql_owned_capacity *domain) {
    return domain_growth_identity_locked(domain) && !domain->growth.parent->closing &&
        !domain->closing && !domain->domain_borrow_attempted;
}

/* Actual placement observation for a known constructor before allocation.
 * This reserves/activates nothing and cannot prove that a later constructor
 * ran. 0 means an original span fits, 1 requires backing, -1 is refusal. */
int actql_native_owned_working_request_status(actql_owned_capacity *domain,
    size_t bytes) {
    if (domain == NULL || bytes == 0 || current_capacity != domain ||
        current_process != getpid() || foreign_domain_process(domain)) return -1;
    lock_capacity(domain);
    int result = -1;
    size_t pages;
    if (domain->closing || !domain->transferred ||
        domain->pending_growth_domain != NULL || domain->growth.state != OWNED_GROWTH_IDLE ||
        !round_pages(bytes, domain->page_size, &pages) ||
        domain->occupied_pages > domain->allocation_ceiling_pages ||
        pages > domain->allocation_ceiling_pages - domain->occupied_pages) goto done;
    result = 1;
    for (size_t start = domain->first_free_page;
         start < domain->page_count && pages <= domain->page_count - start;) {
        size_t free_pages = 0;
        while (free_pages < pages && owned_extent(domain, start + free_pages)->pages == 0)
            free_pages++;
        if (free_pages == pages) { result = 0; break; }
        start += free_pages + 1;
    }
 done:
    unlock_capacity(domain);
    return result;
}

int actql_native_owned_domain_growth_eligible(actql_owned_capacity *domain,
    actql_owned_extent_view *view) {
    return domain != NULL && view != NULL && view->original == view &&
        view->local_loan != NULL && view->local_loan->owner != NULL &&
        !domain->fd_backed && !view->local_loan->owner->fd_backed &&
        whole_local_domain_view(view, view->local_loan->owner) &&
        actql_native_owned_domain_matches_view(domain, view, getpid()) == ACTQL_OWNED_OK;
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
    if (domain->allocation_ceiling_attempted &&
        (domain->occupied_pages > domain->allocation_ceiling_pages ||
         child_controls / domain->page_size >
             domain->allocation_ceiling_pages - domain->occupied_pages)) {
        status = ACTQL_OWNED_EXHAUSTED;
        goto done;
    }
    growth->expected_parent = parent->length;
    growth->expected_domain = domain->length;
    growth->parent_bytes = root_bytes;
    growth->parent_controls = root_controls;
    growth->domain_bytes = child_bytes;
    growth->domain_controls = child_controls;
    growth->state = OWNED_GROWTH_QUOTED;
    growth->outcome = ACTQL_OWNED_GROWTH_PENDING;
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
    case 7: *out = growth->outcome; break;
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
    growth->outcome = ACTQL_OWNED_GROWTH_NO_ACQUISITION;
    if (!domain_growth_original_locked(domain) || parent->pending_growth_domain != NULL ||
        parent->length != growth->expected_parent || domain->length != growth->expected_domain)
        goto done;
    parent->pending_growth_domain = domain;
    growth->state = OWNED_GROWTH_ACQUIRING;
    growth->outcome = ACTQL_OWNED_GROWTH_PENDING;
    uint64_t controls = 0;
    status = grow_capacity_locked(parent, growth->expected_parent, growth->parent_bytes,
                                  sizeof(struct owned_growth_receipt), &controls);
    if (status != ACTQL_OWNED_OK) {
        growth->state = OWNED_GROWTH_REFUSED;
        growth->outcome = ACTQL_OWNED_GROWTH_NO_ACQUISITION;
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
        &receipt->view, growth->expected_domain, &controls, true);
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
        growth->outcome = ACTQL_OWNED_GROWTH_ATTACHED_COMMITTED;
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
        growth->outcome = ACTQL_OWNED_GROWTH_NO_ACQUISITION;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(domain);
    return status;
}

/* Exact physical correspondence, not a state-enum guess. A partial outcome
 * may already have attached its view before a later acknowledgment mismatch. */
static bool pending_domain_growth_receipt_locked(actql_owned_capacity *domain,
    struct owned_growth_receipt *receipt, bool *attached) {
    struct owned_domain_growth *growth = &domain->growth;
    actql_owned_capacity *parent = growth->parent;
    size_t page = parent->page_size;
    if (page == 0 || domain->page_size != page ||
        growth->expected_parent % page != 0 || growth->expected_domain % page != 0 ||
        growth->parent_bytes % page != 0 || growth->parent_controls % page != 0 ||
        growth->domain_bytes % page != 0 || growth->domain_controls % page != 0 ||
        growth->parent_controls == 0 || growth->parent_controls >= growth->parent_bytes ||
        growth->domain_controls == 0 || growth->domain_controls >= growth->domain_bytes ||
        growth->expected_parent > PTRDIFF_MAX ||
        growth->parent_bytes > PTRDIFF_MAX - growth->expected_parent ||
        growth->expected_domain > PTRDIFF_MAX ||
        growth->domain_bytes > PTRDIFF_MAX - growth->expected_domain) return false;
    if (receipt == NULL || receipt != growth->receipts ||
        parent->pending_growth_domain != domain ||
        parent->length != growth->expected_parent + growth->parent_bytes)
        return false;
    struct owned_segment *mapping = parent->segments;
    while (mapping != NULL && mapping != receipt->mapping) mapping = mapping->next;
    if (mapping == NULL || mapping->borrowed_view != NULL ||
        mapping->first_page != growth->expected_parent / parent->page_size ||
        mapping->page_count != growth->parent_bytes / parent->page_size ||
        mapping->control_pages != growth->parent_controls / parent->page_size ||
        receipt != (void *)((unsigned char *)mapping + sizeof(*mapping) +
                           mapping->page_count * sizeof(struct extent))) return false;
    struct owned_segment *selected = NULL;
    for (struct owned_segment *segment = domain->segments; segment != NULL; segment = segment->next) {
        if (segment->borrowed_view != &receipt->view) continue;
        if (selected != NULL) return false;
        selected = segment;
    }
    *attached = selected != NULL;
    if (*attached) {
        return receipt->allocation != NULL && !receipt->allocation_retired &&
            receipt->view.domain_live && receipt->view.domain_attempted &&
            whole_local_domain_view(&receipt->view, parent) &&
            receipt->view.mapping == receipt->allocation &&
            receipt->view.local_loan == &receipt->loan &&
            receipt->view.length == growth->domain_bytes &&
            selected == (void *)receipt->allocation &&
            selected->first_page == growth->expected_domain / domain->page_size &&
            selected->page_count == growth->domain_bytes / domain->page_size &&
            selected->control_pages == growth->domain_controls / domain->page_size &&
            domain->length == growth->expected_domain + growth->domain_bytes;
    }
    if (receipt->view.domain_live || receipt->view.domain_attempted ||
        domain->length != growth->expected_domain ||
        (receipt->allocation_retired && receipt->allocation == NULL)) return false;
    if (receipt->allocation != NULL && !receipt->allocation_retired) {
        size_t start;
        if (!allocation_start(parent, receipt->allocation, &start) ||
            !owned_extent(parent, start)->domain_storage ||
            owned_extent(parent, start)->pages != growth->domain_bytes / parent->page_size)
            return false;
    }
    if (receipt->loan.original != NULL &&
        (receipt->loan.original != &receipt->loan || receipt->loan.owner != parent ||
         receipt->allocation == NULL || receipt->loan.extent.length != growth->domain_bytes ||
         owned_page_address(parent, receipt->loan.start) != receipt->allocation ||
         receipt->loan.local_process != (int64_t)getpid() ||
         receipt->loan.extent.generation != parent->generation ||
         receipt->loan.extent.device != parent->backing_device ||
         receipt->loan.extent.inode != parent->backing_inode ||
         memcmp(receipt->loan.extent.recipe, parent->recipe, sizeof(parent->recipe)) != 0)) return false;
    if (receipt->view.original != NULL &&
        (receipt->view.original != &receipt->view ||
         receipt->view.local_loan != &receipt->loan ||
         receipt->loan.original != &receipt->loan ||
         receipt->view.length != growth->domain_bytes ||
         memcmp(&receipt->view.extent, &receipt->loan.extent,
                sizeof(receipt->view.extent)) != 0)) return false;
    return true;
}

/* Scalar original cleanup only: no managed constructor, payload entry, TLS
 * substitution, new mapping, or logical byte refund. Old inactive aliases may
 * remain. A later constructor still needs its own already funded controls. */
int actql_native_owned_reconcile_domain_growth(actql_owned_capacity *domain,
    actql_owned_extent_view *original_view, uint64_t serial, unsigned *outcome) {
    if (domain == NULL || original_view == NULL || outcome == NULL || *outcome != 0 ||
        serial == 0 || !actql_native_owned_control_scope_clear() ||
        domain->growth.parent == NULL || original_view != domain->growth.original_view)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = domain->growth.parent;
    if (foreign_domain_process(parent) || foreign_domain_process(domain)) return ACTQL_OWNED_BUSY;
    lock_capacity(parent);
    lock_capacity(domain);
    struct owned_domain_growth *growth = &domain->growth;
    int status = ACTQL_OWNED_INVALID;
    if (domain->active_scopes != 0 || growth->serial != serial ||
        !domain_growth_identity_locked(domain)) goto done;
    if (growth->state == OWNED_GROWTH_IDLE && growth->pending == NULL &&
        growth->outcome >= ACTQL_OWNED_GROWTH_NO_ACQUISITION &&
        growth->outcome <= ACTQL_OWNED_GROWTH_CHILD_RETIRED_ROOT_RETAINED &&
        parent->pending_growth_domain != domain) {
        *outcome = growth->outcome;
        status = ACTQL_OWNED_OK;
        goto done;
    }
    if (growth->state != OWNED_GROWTH_PARTIAL && growth->state != OWNED_GROWTH_ATTACHED)
        goto done;
    struct owned_growth_receipt *receipt = growth->pending;
    bool attached = false;
    if (!pending_domain_growth_receipt_locked(domain, receipt, &attached)) goto done;
    if (!attached) {
        if (receipt->view.original != NULL && receipt->view.mapping != NULL) {
            status = actql_native_owned_close_extent_view(&receipt->view);
            if (status != ACTQL_OWNED_OK) goto done;
        }
        if (receipt->loan.original != NULL && !receipt->loan.returned) {
            status = return_extent_locked(&receipt->loan);
            if (status != ACTQL_OWNED_OK) goto done;
        }
        if (receipt->allocation != NULL && !receipt->allocation_retired) {
            status = retire_allocation_locked(parent, receipt->allocation);
            if (status != ACTQL_OWNED_OK) goto done;
            receipt->allocation_retired = true;
        }
    }
    /* Keep the root mapping and its self-hosted historical receipt. This
     * terminal serial remains observable until the next original quote. */
    growth->outcome = attached ? ACTQL_OWNED_GROWTH_ATTACHED_COMMITTED :
                                ACTQL_OWNED_GROWTH_CHILD_RETIRED_ROOT_RETAINED;
    growth->state = OWNED_GROWTH_IDLE;
    growth->pending = NULL;
    parent->pending_growth_domain = NULL;
    *outcome = growth->outcome;
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(domain);
    unlock_capacity(parent);
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
