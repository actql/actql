/* Private enclosing control lifetime on the same transferred root allocator.
 * Constructor inventories, not logical-byte tariffs, select each cohort. This
 * first closed family covers requests proven to fit one existing slab page;
 * it is not a variable payload limit or an installed Request layout proof.
 * Count every allocator request, including sequential ones: a failed physical
 * retirement can retain the old page after its last managed alias is gone. */
#if defined(ACTQL_SCOPED_READ_ALLOCATOR) && defined(ACTQL_SCOPED_READ_PROVIDER) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER) && !defined(ACTQL_RUNTIME_MANAGED_VALUES)
#define ACTQL_ROOT_CONTROL_CONTEXT 1
#endif

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_root_control_quote(
    actql_bootstrap_backing *record, int64_t maximum_request, int64_t requests,
    int32_t include_context) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->lease == NULL || record->lease->extent_domain ||
        record->status != ACTQL_OWNED_OK || maximum_request <= 0 || requests <= 0 ||
        (uint64_t)maximum_request > SIZE_MAX || (uint64_t)requests > SIZE_MAX ||
        (include_context != 0 && include_context != 1)) return -1;
    size_t page = record->lease->page_size;
    size_t rounded = read_heap_round((size_t)maximum_request);
    size_t overhead = read_heap_round(sizeof(struct read_heap_page)) + read_heap_header();
    /* The selected allocator takes the slab route only for this closed family.
     * Check actual metadata too; a different ABI must not inherit this proof. */
    if ((size_t)maximum_request > page / 2 || !rounded || overhead > page ||
        rounded > page - overhead || sizeof(actql_read_context) > page ||
        (uint64_t)requests > (uint64_t)INT64_MAX / page - (uint64_t)include_context)
        return -1;
    return (requests + include_context) * (int64_t)page;
#else
    (void)record; (void)maximum_request; (void)requests; (void)include_context;
    return -1;
#endif
}

/* Observation under the existing root scope, never capacity admission. Each
 * requested control fits a single page, so no multi-page contiguity is inferred
 * from aggregate free storage. All previous cohorts remain separately charged. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_root_control_available(
    actql_bootstrap_backing *record, int64_t bytes) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->lease == NULL || bytes <= 0 ||
        actql_read_context_current() != NULL) return ACTQL_OWNED_INVALID;
    uint64_t values[16] = {0};
    int status = actql_native_owned_inventory(record->lease, values, 16);
    if (status != ACTQL_OWNED_OK) return status;
    return (uint64_t)bytes <= values[0] - values[3]
        ? ACTQL_OWNED_OK : ACTQL_OWNED_EXHAUSTED;
#else
    (void)record; (void)bytes;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_prepare_root_control(
    actql_bootstrap_backing *record, int64_t maximum, int64_t requests) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->lease == NULL || record->lease->extent_domain ||
        record->control_attempted || maximum <= 0 || requests <= 0 ||
        (uint64_t)maximum > SIZE_MAX || (uint64_t)requests > SIZE_MAX ||
        actql_read_context_current() != NULL ||
        actql_native_owned_current() != record->lease) return ACTQL_OWNED_INVALID;
    record->control_attempted = true;
    int status = actql_read_context_create(record->lease, &record->control_context);
    if (status == ACTQL_OWNED_OK) {
        status = actql_read_context_retain(record->control_context);
        if (status == ACTQL_OWNED_OK) record->control_user = true;
    }
    if (status == ACTQL_OWNED_OK)
        status = actql_read_context_prepare_managed(record->control_context,
                                                    (size_t)maximum, (size_t)requests);
    return status;
#else
    (void)record; (void)maximum; (void)requests;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_extend_root_control(
    actql_bootstrap_backing *record, int64_t maximum, int64_t requests) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->control_context == NULL || !record->control_user ||
        record->control_active != 0 || maximum <= 0 || requests <= 0 ||
        (uint64_t)maximum > SIZE_MAX || (uint64_t)requests > SIZE_MAX)
        return ACTQL_OWNED_INVALID;
    return actql_read_context_prepare_managed(record->control_context,
                                               (size_t)maximum, (size_t)requests);
#else
    (void)record; (void)maximum; (void)requests;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_enter_root_control(
    actql_bootstrap_backing *record) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->control_context == NULL || !record->control_user ||
        record->control_active != 0 || actql_read_context_current() != NULL ||
        actql_native_owned_current() != record->lease) return ACTQL_OWNED_INVALID;
    int status = actql_read_context_enter(record->control_context);
    if (status == ACTQL_OWNED_OK) record->control_active = 1;
    return status;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_leave_root_control(
    actql_bootstrap_backing *record) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->control_context == NULL || record->control_active != 1 ||
        actql_read_context_current() != record->control_context ||
        actql_native_owned_current() != record->lease) return ACTQL_OWNED_INVALID;
    int status = actql_read_context_leave(record->control_context);
    if (status == ACTQL_OWNED_OK) record->control_active = 0;
    return status;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* The original owning root scope, outside every child/read frame. This
 * observes the same context only; it never creates a user or grants storage. */
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
static bool root_control_finish_current_locked(actql_bootstrap_backing *record) {
    return record != NULL && record->lease != NULL &&
        record->status == ACTQL_OWNED_OK && record->control_context != NULL &&
        known_read_context(record->control_context) && record->control_user &&
        record->control_active == 0 && read_current == NULL && read_depth == 0 &&
        actql_native_owned_current() == record->lease &&
        record->control_context->lease == record->lease &&
        record->control_context->users == 1 && record->control_context->active == 0 &&
        !record->control_context->closing &&
        pthread_equal(record->control_context->observation_thread, pthread_self());
}
#endif

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_root_control_generation(
    actql_bootstrap_backing *record) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (!lock_read_contexts()) return ACTQL_OWNED_INVALID;
    int64_t result = ACTQL_OWNED_INVALID;
    if (root_control_finish_current_locked(record) &&
        record->control_context->managed_generation > 0 &&
        record->control_context->managed_generation <= INT64_MAX)
        result = (int64_t)record->control_context->managed_generation;
    unlock_read_contexts();
    return result;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Reconcile only after the SAME managed generation has actually finished.
 * Its existing finish cancels unused constructor permissions and physically
 * retires empty/pending cohort pages. Live old aliases keep their real pages.
 * This is not a free-space estimate, GC liveness inference or new byte grant. */
MOONBIT_FFI_EXPORT int64_t actql_bootstrap_finish_root_control_cohort(
    actql_bootstrap_backing *record, int64_t generation) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (generation <= 0 || !lock_read_contexts()) return ACTQL_OWNED_INVALID;
    bool current = root_control_finish_current_locked(record) &&
        record->control_context->managed_generation == (uint64_t)generation;
    unlock_read_contexts();
    if (!current) return ACTQL_OWNED_INVALID;
    int status = actql_read_context_finish_managed(record->control_context,
                                                  (uint64_t)generation);
    if (status != ACTQL_OWNED_OK) return status;
    uint64_t values[16] = {0};
    status = actql_read_context_cleanup_snapshot(record->control_context, values, 16);
    if (status != ACTQL_OWNED_OK) return status;
    if (values[0] != 1 || values[1] != 0 || values[2] != 0 || values[3] != 0 ||
        values[8] != 0 || values[9] != 0 || values[12] != 0 ||
        values[13] != 0 || values[14] != 1) return ACTQL_OWNED_BUSY;
    if (!lock_read_contexts()) return ACTQL_OWNED_INVALID;
    int64_t result = ACTQL_OWNED_INVALID;
    if (root_control_finish_current_locked(record) &&
        record->control_context->managed_generation == (uint64_t)generation &&
        !record->control_context->managed_cohort &&
        !record->control_context->managed_preparing &&
        !record->control_context->managed_finishing) {
        actql_owned_capacity *lease = record->lease;
        lock_capacity(lease);
        size_t index;
        if (!lease->closing && allocation_start(lease, record->control_context, &index)) {
            struct extent *extent = owned_extent(lease, index);
            if (!extent->retired && extent->pages != 0 && extent->pages != SIZE_MAX &&
                extent->pages <= lease->page_count - index &&
                values[4] <= (uint64_t)INT64_MAX / lease->page_size &&
                extent->pages <= (uint64_t)INT64_MAX / lease->page_size - values[4])
                result = (int64_t)((values[4] + extent->pages) * lease->page_size);
        }
        unlock_capacity(lease);
    }
    unlock_read_contexts();
    return result;
#else
    (void)record; (void)generation;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_close_root_control(
    actql_bootstrap_backing *record) {
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->control_active != 0 ||
        actql_read_context_current() != NULL) return ACTQL_OWNED_INVALID;
    if (record->control_user) {
        int status = actql_read_context_release_after_owner_ack(record->control_context);
        if (status != ACTQL_OWNED_OK) return status;
        record->control_user = false;
    }
    if (record->control_context == NULL) return ACTQL_OWNED_OK;
    return actql_read_context_try_close(&record->control_context);
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Request controls may outlive their child's Read. The only entered alternative
 * to ordinary clear scope is this exact enclosing root and its original child
 * chain. This is an identity observation, not a scope switch or a funding quote.
 * The nominal MoonBit graph retains every borrowed external record here. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_request_control_scope(
    actql_bootstrap_backing *record, actql_bootstrap_domain *domain) {
    if (actql_bootstrap_control_scope_clear() == 1) return 1;
#if defined(ACTQL_ROOT_CONTROL_CONTEXT)
    if (record == NULL || record->lease == NULL || record->control_context == NULL ||
        !record->control_user || record->control_active != 1 ||
        actql_native_owned_current() != record->lease ||
        actql_read_context_current() != record->control_context ||
        domain == NULL || domain->lease == NULL || domain->read_active != 0 ||
        domain->read_prepare_scope || domain->view == NULL)
        return 0;
    actql_bootstrap_view *view = domain->view;
    actql_bootstrap_region *loan = view->loan;
    if (loan == NULL || loan->owner != record || loan->extent == NULL ||
        loan->extent->owner != record || loan->extent->address == NULL ||
        loan->loan.original != &loan->loan || loan->loan.owner != record->lease ||
        loan->loan.returned || view->view.original != &view->view ||
        (view->view.local_loan != NULL && view->view.local_loan != &loan->loan))
        return 0;
    return actql_native_owned_domain_matches_view(domain->lease, &view->view,
                                                  (int64_t)getpid()) == ACTQL_OWNED_OK;
#else
    (void)record; (void)domain;
    return 0;
#endif
}
