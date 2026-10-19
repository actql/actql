/* Fixed control record in the existing Host/process custody. The descriptor
 * aliases the original backing; its independent control/FD cost is not funded
 * by the delegated arena. No finalizer can acknowledge its cleanup. */
typedef struct {
    actql_bootstrap_view *view;
    actql_bootstrap_domain *domain;
    pid_t origin;
    int descriptor;
    int child;
    int status;
    bool unborrowed_cleanup;
    bool unmapped;
    bool close_unknown;
    bool closed;
} actql_bootstrap_process_region;

static bool process_region_original(actql_bootstrap_process_region *record) {
    return record != NULL && record->origin == getpid() && record->view != NULL &&
        record->domain != NULL && record->domain->view == record->view;
}

static bool process_region_fd_identity(int fd, size_t bytes, struct stat *value) {
    int flags = fcntl(fd, F_GETFL);
    return flags >= 0 && (flags & O_ACCMODE) == O_RDWR &&
        fstat(fd, value) == 0 && S_ISREG(value->st_mode) &&
        (value->st_mode & 0777) == 0600 && value->st_uid == geteuid() &&
        value->st_nlink <= 1 && value->st_size >= 0 && (uint64_t)value->st_size == bytes;
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_capture_process_region(
    actql_bootstrap_view *view, actql_bootstrap_domain *domain, int32_t fd) {
    actql_bootstrap_process_region *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->view = view;
    record->domain = domain;
    record->origin = getpid();
    record->descriptor = -1;
    record->status = ACTQL_OWNED_INVALID;
    if (view == NULL || domain == NULL || domain->view != view ||
        view->status != ACTQL_OWNED_OK || domain->status != ACTQL_OWNED_OK ||
        actql_native_owned_domain_unborrowed(domain->lease, &view->view) != ACTQL_OWNED_OK ||
        !view->view.extent.writable)
        return record;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (domain->read_context != NULL || domain->read_user ||
        domain->read_active != 0 || domain->read_prepare_scope) {
        record->status = ACTQL_OWNED_BUSY;
        return record;
    }
#endif
    struct stat before;
    if (!process_region_fd_identity(fd, view->view.extent.capacity, &before) ||
        (uint64_t)before.st_dev != view->view.extent.device ||
        (uint64_t)before.st_ino != view->view.extent.inode)
        return record;
    /* Capture before spawn. The existing Native Owner retains this partial
     * carrier before inspecting status; a post-dup failure still owns the FD. */
    record->descriptor = fcntl(fd, F_DUPFD_CLOEXEC, 10);
    if (record->descriptor < 0) {
        record->status = ACTQL_OWNED_PHYSICAL_FAILURE;
        return record;
    }
    struct stat after;
    record->status = process_region_fd_identity(record->descriptor, view->view.extent.capacity, &after) &&
        before.st_dev == after.st_dev && before.st_ino == after.st_ino
        ? ACTQL_OWNED_OK : ACTQL_OWNED_PHYSICAL_FAILURE;
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_process_region_status(
    actql_bootstrap_process_region *record) {
    return process_region_original(record) ? record->status : ACTQL_OWNED_INVALID;
}

/* Borrow only the descriptor captured by this original before spawn. The
 * existing process Owner may duplicate it into its prepared child transport;
 * this does not transfer close responsibility or grant execution authority. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_prepared_process_region_descriptor(
    actql_bootstrap_process_region *record) {
    if (!process_region_original(record) || record->status != ACTQL_OWNED_OK ||
        record->closed || record->unmapped || record->close_unknown ||
        record->child != 0 || record->descriptor < 0 ||
        record->view->status != ACTQL_OWNED_OK ||
        record->domain->status != ACTQL_OWNED_OK ||
        actql_native_owned_domain_unborrowed(record->domain->lease,
            &record->view->view) != ACTQL_OWNED_OK)
        return -1;
    struct stat value;
    int flags = fcntl(record->descriptor, F_GETFD);
    if (flags < 0 || !(flags & FD_CLOEXEC) ||
        !process_region_fd_identity(record->descriptor,
            record->view->view.extent.capacity, &value) ||
        (uint64_t)value.st_dev != record->view->view.extent.device ||
        (uint64_t)value.st_ino != record->view->view.extent.inode)
        return -1;
    return record->descriptor;
}

static int process_region_close_descriptor(actql_bootstrap_process_region *record) {
    if (record->close_unknown) return ACTQL_OWNED_PHYSICAL_FAILURE;
    if (record->descriptor < 0) return ACTQL_OWNED_OK;
    int descriptor = record->descriptor;
    /* A close can consume its FD before losing the result. Never retry the
     * number and accidentally close a foreign reused descriptor. */
    record->descriptor = -1;
    if (close(descriptor) != 0) {
        record->close_unknown = true;
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    }
    return ACTQL_OWNED_OK;
}

/* A successful child borrow return publishes zero only after releasing its
 * allocator lock. Its closing/attempted state deliberately remains sticky.
 * This is original-header correspondence, never a stop or cleanup proof: the
 * Native process Owner must still validate its same Holder's typed stop, and
 * ordinary allocation-level close below must confirm every remaining user. */
static bool process_region_domain_returned(actql_bootstrap_process_region *record) {
    return actql_native_owned_domain_returned(record->domain->lease,
        &record->view->view) == ACTQL_OWNED_OK;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_abandon_prepared_process_region(
    actql_bootstrap_process_region *record) {
    /* The Native caller also requires its original unstarted holder. This
     * physical check cannot manufacture that proof from allocator metadata. */
    if (!process_region_original(record) || record->unmapped || record->child != 0)
        return ACTQL_OWNED_INVALID;
    if (record->closed) return ACTQL_OWNED_OK;
    /* Undo only this never-started preparation's descriptor capture. Domain
     * readiness may itself have been the primary refusal. Do not change its
     * allocator, borrower, view or loan, or claim that any region retired. */
    int status = process_region_close_descriptor(record);
    if (status == ACTQL_OWNED_OK) record->closed = true;
    return status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_retire_stopped_process_region(
    actql_bootstrap_process_region *record, int32_t child) {
    /* NativeScopedExecutorStop::require_current(original_holder) MUST precede
     * this call. The PID checks physical correspondence only, never stop. */
    if (!process_region_original(record) || child <= 0 ||
        (record->child != 0 && record->child != child)) return ACTQL_OWNED_INVALID;
    if (record->closed) return record->unmapped ? ACTQL_OWNED_OK : ACTQL_OWNED_INVALID;
    /* Cleanup is independent of the original capture's primary result. Keep
     * that status unchanged even if the original stopped carrier can retire
     * its partial descriptor/view; cleanup never promotes Pending to Ready. */
    if (!record->unmapped) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
        if (record->domain->read_context != NULL || record->domain->read_user ||
            record->domain->read_active != 0 || record->domain->read_prepare_scope)
            return ACTQL_OWNED_BUSY;
#endif
        if (record->child == 0) {
            /* Never-borrowed startup and confirmed normal borrow return both
             * use ordinary allocation-level close. A returned child's sticky
             * closing state must not force the retained-borrow bypass. */
            if (actql_native_owned_domain_unborrowed(record->domain->lease,
                    &record->view->view) == ACTQL_OWNED_OK ||
                process_region_domain_returned(record))
                record->unborrowed_cleanup = true;
            else if (actql_native_owned_domain_has_child(record->domain->lease,
                    (int64_t)getpid(), child) != ACTQL_OWNED_OK)
                return ACTQL_OWNED_INVALID;
            record->child = child;
        }
        int status;
        if (record->unborrowed_cleanup) {
            status = actql_native_owned_close_extent_domain(
                &record->view->view, &record->domain->lease);
            if (status == ACTQL_OWNED_OK)
                status = actql_native_owned_close_extent_view(&record->view->view);
        } else {
            status = actql_native_owned_unmap_stopped_child_domain(
                &record->view->view, &record->domain->lease);
        }
        if (status != ACTQL_OWNED_OK) return status;
        record->unmapped = true;
    }
    int status = process_region_close_descriptor(record);
    if (status == ACTQL_OWNED_OK) record->closed = true;
    return status;
}
