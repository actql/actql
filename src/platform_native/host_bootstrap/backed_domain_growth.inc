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
