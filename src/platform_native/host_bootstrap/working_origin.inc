/* Source-private physical custody prerequisite. These functions are deliberately
 * not FFI exports: the Common Resource issuer and its complete constructor
 * certificate must exist before this carrier can authorize any admission/grow.
 * Resource references below retain originals; they do not authenticate them. */
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
typedef struct {
    actql_bootstrap_backing *root;
    actql_bootstrap_extent *extent;
    void *capacity, *allocation, *borrow;
    actql_bootstrap_region *loan;
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
    void *domain_original;
    uint64_t root_generation, domain_generation;
    pid_t process;
    pthread_t thread;
    bool bind_attempted, bound, revoked;
} actql_bootstrap_working_origin;

/* The enclosing Read funds exactly this external-object request before entry.
 * No guessed Moon header, multiplier or logical payload tariff is accepted. */
static int64_t working_origin_raw_bytes(void) {
    size_t bytes;
    return component_receiver_raw(sizeof(actql_bootstrap_working_origin), &bytes) &&
        bytes <= INT64_MAX ? (int64_t)bytes : -1;
}

/* Read-index lock is held before taking the existing capacity lock. */
static bool working_root_control_current(actql_bootstrap_backing *root) {
    return root != NULL && root->lease != NULL && root->status == ACTQL_OWNED_OK &&
        root->control_context != NULL && known_read_context(root->control_context) &&
        root->control_user && root->control_active == 1 &&
        read_current == root->control_context && read_depth == 1 &&
        root->control_context->active == 1 && !root->control_context->closing &&
        pthread_equal(root->control_context->observation_thread, pthread_self()) &&
        actql_native_owned_current() == root->lease && current_process == getpid() &&
        !root->lease->fd_backed && !root->lease->extent_domain &&
        !foreign_domain_process(root->lease);
}

/* Only an unborrowed original private domain allocation can be selected.
 * Publication is one-shot even after revocation; equal bytes do not recreate it.
 * The caller already owns the same nominal Resource claim and owner borrow. */
static actql_bootstrap_working_origin *working_origin_select(
    actql_bootstrap_backing *root, actql_bootstrap_extent *extent,
    void *capacity, void *allocation, void *borrow) {
    if (capacity == NULL || allocation == NULL || borrow == NULL ||
        extent == NULL || extent->owner != root || extent->working_selected ||
        !extent->domain_storage || extent->status != ACTQL_OWNED_OK ||
        !lock_read_contexts()) return NULL;
    bool valid = false;
    uint64_t generation = 0;
    int64_t raw = working_origin_raw_bytes();
    if (working_root_control_current(root) && raw > 0 &&
        root->control_context->managed_prepared &&
        !root->control_context->managed_preparing &&
        !root->control_context->managed_finishing &&
        root->control_context->managed_remaining > 0 &&
        (uint64_t)raw <= root->control_context->managed_maximum) {
        lock_capacity(root->lease);
        size_t index;
        if (!root->lease->closing && root->lease->transferred &&
            !root->lease->allocation_ceiling_attempted &&
            root->lease->pending_growth_domain == NULL &&
            allocation_start(root->lease, extent->address, &index)) {
            struct extent *physical = owned_extent(root->lease, index);
            valid = physical->domain_storage && !physical->retired &&
                !allocation_has_external_use(root->lease, index, false);
            generation = root->lease->generation;
        }
        unlock_capacity(root->lease);
    }
    unlock_read_contexts();
    if (!valid) return NULL;
    /* This fixed, non-reentrant constructor uses the already entered cohort.
     * It acquires no physical mapping or new Resource claim. */
    actql_bootstrap_working_origin *value = moonbit_make_external_object(
        keep_physical_custody, sizeof(*value));
    memset(value, 0, sizeof(*value));
    value->root = root; value->extent = extent;
    value->capacity = capacity; value->allocation = allocation; value->borrow = borrow;
    value->root_generation = generation;
    value->process = getpid(); value->thread = pthread_self();
    moonbit_incref(root); moonbit_incref(extent);
    moonbit_incref(capacity); moonbit_incref(allocation); moonbit_incref(borrow);
    extent->working_selected = true;
    return value;
}

static bool working_origin_thread(actql_bootstrap_working_origin *value) {
    return value != NULL && value->process == getpid() &&
        pthread_equal(value->thread, pthread_self());
}

/* Retain the entire nominal domain graph before validating the physical bind.
 * Failed/partial binding stays with this exact carrier until domain retirement.
 * This port does NOT prepare growth or publish a child admission. */
static int working_origin_bind(actql_bootstrap_working_origin *value,
    actql_bootstrap_region *loan, actql_bootstrap_view *view,
    actql_bootstrap_domain *domain, void *domain_original) {
    if (!working_origin_thread(value) || value->revoked || value->bind_attempted ||
        loan == NULL || view == NULL || domain == NULL || domain_original == NULL ||
        loan->owner != value->root || loan->extent != value->extent ||
        view->loan != loan || domain->view != view) return ACTQL_OWNED_INVALID;
    value->bind_attempted = true;
    value->loan = loan; value->view = view; value->domain = domain;
    value->domain_original = domain_original;
    moonbit_incref(loan); moonbit_incref(view); moonbit_incref(domain);
    moonbit_incref(domain_original);
    if (!lock_read_contexts()) return ACTQL_OWNED_INVALID;
    int status = ACTQL_OWNED_INVALID;
    if (working_root_control_current(value->root) && domain->lease != NULL &&
        domain->lease != value->root->lease &&
        domain->status == ACTQL_OWNED_OK && !domain->read_prepare_scope &&
        domain->read_active == 0) {
        actql_owned_capacity *root = value->root->lease;
        actql_owned_capacity *child = domain->lease;
        lock_capacity(root);
        lock_capacity(child);
        if (root->generation == value->root_generation && !root->closing &&
            !child->closing && child->active_scopes == 0 && child->transferred &&
            !child->domain_borrow_attempted && !child->allocation_ceiling_attempted &&
            child->growth.parent == NULL && root->pending_growth_domain == NULL &&
            !foreign_domain_process(child) &&
            atomic_load_explicit(&child->domain_borrower_pid, memory_order_acquire) == 0 &&
            whole_local_domain_view(&view->view, root) &&
            actql_native_owned_domain_matches_view(child, &view->view, getpid()) == ACTQL_OWNED_OK) {
            value->domain_generation = child->generation;
            value->bound = true;
            status = ACTQL_OWNED_OK;
        }
        unlock_capacity(child);
        unlock_capacity(root);
    }
    unlock_read_contexts();
    return status;
}

/* No allocation, cleanup inference or GC ACK. The existing close_domain port
 * must actually have nulled the exact retained lease and cleared domain_live.
 * Revocation precedes decrefs so escaped aliases cannot retain authority. */
static int working_origin_revoke_after_domain_retirement(
    actql_bootstrap_working_origin *value) {
    if (!working_origin_thread(value)) return ACTQL_OWNED_INVALID;
    if (value->revoked) return ACTQL_OWNED_OK;
    if (value->domain != NULL &&
        (value->domain->lease != NULL || value->view->view.domain_live))
        return ACTQL_OWNED_BUSY;
    value->revoked = true;
    value->bound = false;
    /* Strong references include borrowed external records AND nominal Resource
     * and domain originals. Dropping an external domain alone is insufficient. */
    void *refs[] = {value->domain_original, value->domain, value->view, value->loan,
        value->borrow, value->allocation, value->capacity, value->extent, value->root};
    value->domain_original = NULL; value->domain = NULL; value->view = NULL;
    value->loan = NULL; value->borrow = NULL; value->allocation = NULL;
    value->capacity = NULL; value->extent = NULL; value->root = NULL;
    for (size_t index = 0; index < sizeof(refs) / sizeof(refs[0]); index++)
        if (refs[index] != NULL) moonbit_decref(refs[index]);
    return ACTQL_OWNED_OK;
}
#endif
