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

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_abandon_prepared_process_region(
    actql_bootstrap_process_region *record) {
    /* The Native caller also requires its original unstarted holder. This
     * physical check cannot manufacture that proof from allocator metadata. */
    if (!process_region_original(record) || record->unmapped)
        return ACTQL_OWNED_INVALID;
    if (record->closed) return ACTQL_OWNED_OK;
    if (actql_native_owned_domain_unborrowed(record->domain->lease,
            &record->view->view) != ACTQL_OWNED_OK)
        return ACTQL_OWNED_INVALID;
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
    if (record->status != ACTQL_OWNED_OK) return record->status;
    if (!record->unmapped) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
        if (record->domain->read_context != NULL || record->domain->read_user ||
            record->domain->read_active != 0 || record->domain->read_prepare_scope)
            return ACTQL_OWNED_BUSY;
#endif
        if (record->child == 0) {
            /* A stopped startup may never have entered the original borrow.
             * The typed stop still precedes cleanup. Such a domain follows
             * ordinary allocation-level close, never whole-region bypass. */
            if (actql_native_owned_domain_unborrowed(record->domain->lease,
                    &record->view->view) == ACTQL_OWNED_OK)
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
