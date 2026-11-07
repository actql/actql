/* Same existing physical domain and parent mapping. These scalar calls create
 * no managed carrier and no new Owner, reservation or logical child allowance. */
static bool bootstrap_growth_original(actql_bootstrap_backing *root,
    actql_bootstrap_domain *domain) {
    return root != NULL && root->lease != NULL && domain != NULL &&
        domain->lease != NULL && domain->view != NULL &&
        domain->view->loan != NULL && domain->view->loan->owner == root &&
        domain->view->loan->extent != NULL &&
        domain->view->loan->extent->domain_storage &&
        domain->view->view.local_loan == &domain->view->loan->loan;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_domain_growth_eligible(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain) {
    return bootstrap_growth_original(root, domain) &&
        actql_native_owned_domain_growth_eligible(domain->lease, &domain->view->view);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_working_request_status(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t bytes) {
    if (!bootstrap_growth_original(root, domain) || bytes <= 0 ||
        (uint64_t)bytes > PTRDIFF_MAX) return -1;
    return actql_native_owned_working_request_status(domain->lease, (size_t)bytes);
}

/* Only the SAME original active Read may select bound growth. Its trusted
 * Common caller checks the original consumer demand; these calls issue
 * no semantic read/Run permission or constructor themselves. */
static bool bootstrap_checked_read_current(actql_bootstrap_backing *root,
    actql_bootstrap_domain *domain) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    return bootstrap_growth_original(root, domain) && domain->read_context != NULL &&
        domain->read_user && domain->read_active != 0 &&
        actql_read_context_current() == domain->read_context &&
        actql_native_owned_current() == domain->lease;
#else
    (void)root; (void)domain;
    return false;
#endif
}

/* Parent accounting must not retain managed control in the child Read.
 * Suspend only its one actual scope; keep the same user/context/generation.
 * Refusal retains this original completed-leave duty for existing cleanup. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_suspend_read_for_parent_accounting(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (!bootstrap_checked_read_current(root, domain) || domain->read_active != 1 ||
        domain->read_parent_suspended) return ACTQL_OWNED_INVALID;
    int status = actql_bootstrap_leave_read_context(domain);
    if (status != ACTQL_OWNED_OK) return status;
    domain->read_parent_suspended = true;
    return actql_read_context_current() == NULL && actql_native_owned_current() == NULL
        ? ACTQL_OWNED_OK : ACTQL_OWNED_BUSY;
#else
    (void)root; (void)domain; return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_resume_read_after_parent_accounting(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (!bootstrap_growth_original(root, domain) || !domain->read_parent_suspended ||
        !domain->read_user || domain->read_active != 0 ||
        actql_read_context_current() != NULL || actql_native_owned_current() != NULL)
        return ACTQL_OWNED_INVALID;
    domain->read_parent_suspended = false;
    int status = actql_bootstrap_enter_read_context(domain);
    if (status != ACTQL_OWNED_OK) domain->read_parent_suspended = true;
    return status;
#else
    (void)root; (void)domain; return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_checked_read_working_status(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t bytes) {
    if (!bootstrap_checked_read_current(root, domain) || bytes <= 0 ||
        (uint64_t)bytes > PTRDIFF_MAX) return -1;
    return actql_native_owned_checked_read_working_status(domain->lease, (size_t)bytes);
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_quote_checked_read_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t bytes) {
    if (!bootstrap_checked_read_current(root, domain) || bytes <= 0 ||
        (uint64_t)bytes > PTRDIFF_MAX) return -1;
    uint64_t serial = 0;
    int status = actql_native_owned_quote_checked_read_growth(domain->lease, (size_t)bytes, &serial);
    return status == ACTQL_OWNED_OK && serial > 0 && serial <= INT64_MAX ? (int64_t)serial : -1;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_quote_checked_read_growth_covering(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain,
    int64_t contiguous_bytes, int64_t minimum_usable_bytes) {
    if (!bootstrap_checked_read_current(root, domain) || contiguous_bytes < 0 ||
        minimum_usable_bytes < 0 || (contiguous_bytes == 0 && minimum_usable_bytes == 0) ||
        (uint64_t)contiguous_bytes > PTRDIFF_MAX ||
        (uint64_t)minimum_usable_bytes > PTRDIFF_MAX) return -1;
    uint64_t serial = 0;
    int status = actql_native_owned_quote_checked_read_growth_covering(domain->lease,
        (size_t)contiguous_bytes, (size_t)minimum_usable_bytes, &serial);
    return status == ACTQL_OWNED_OK && serial > 0 && serial <= INT64_MAX ? (int64_t)serial : -1;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_prepare_domain_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain) {
    if (!bootstrap_growth_original(root, domain)) return ACTQL_OWNED_INVALID;
    return actql_native_owned_prepare_domain_growth(domain->lease, &domain->view->view);
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_quote_domain_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t bytes) {
    if (!bootstrap_growth_original(root, domain) || bytes <= 0 ||
        (uint64_t)bytes > PTRDIFF_MAX) return -1;
    uint64_t serial = 0;
    int status = actql_native_owned_quote_domain_growth(domain->lease, (size_t)bytes, &serial);
    return status == ACTQL_OWNED_OK && serial > 0 && serial <= INT64_MAX ? (int64_t)serial : -1;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_domain_growth_scalar(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t serial, int32_t field) {
    if (!bootstrap_growth_original(root, domain) || serial <= 0 || field < 0) return -1;
    uint64_t value = 0;
    int status = actql_native_owned_domain_growth_scalar(domain->lease, (uint64_t)serial,
                                                         (unsigned)field, &value);
    return status == ACTQL_OWNED_OK && value <= INT64_MAX ? (int64_t)value : -1;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_acquire_domain_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t serial) {
    if (!bootstrap_growth_original(root, domain) || serial <= 0) return ACTQL_OWNED_INVALID;
    return actql_native_owned_acquire_domain_growth(domain->lease, (uint64_t)serial);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_finish_domain_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t serial) {
    if (!bootstrap_growth_original(root, domain) || serial <= 0) return ACTQL_OWNED_INVALID;
    return actql_native_owned_finish_domain_growth(domain->lease, (uint64_t)serial);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_cancel_domain_growth_quote(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t serial) {
    if (!bootstrap_growth_original(root, domain) || serial <= 0) return ACTQL_OWNED_INVALID;
    return actql_native_owned_cancel_domain_growth_quote(domain->lease, (uint64_t)serial);
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_reconcile_domain_growth(
    actql_bootstrap_backing *root, actql_bootstrap_domain *domain, int64_t serial) {
    if (!bootstrap_growth_original(root, domain) || serial <= 0) return -1;
    unsigned outcome = ACTQL_OWNED_GROWTH_PENDING;
    int status = actql_native_owned_reconcile_domain_growth(domain->lease,
        &domain->view->view, (uint64_t)serial, &outcome);
    return status == ACTQL_OWNED_OK ? (int64_t)outcome : -1;
}
