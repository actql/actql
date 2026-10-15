/* Borrowed physical observations only. The managed original domain/ticket is
 * the authority. PID, descriptors, nonce and relative span DATA are not one.
 * No descriptor is opened, duplicated, sent, closed or inferred retired here. */
typedef struct actql_bootstrap_live_channel {
    struct actql_bootstrap_live_channel *original;
    actql_bootstrap_domain *domain;
    actql_owned_capacity *lease;
    pid_t process;
    pid_t child;
    int read_fd;
    int write_fd;
    dev_t read_device;
    ino_t read_inode;
    dev_t write_device;
    ino_t write_inode;
    int64_t nonce;
    size_t span_offset;
    size_t span_bytes;
    int status;
    bool binding_attempted;
    bool bound;
    bool retired;
} actql_bootstrap_live_channel;

static bool original_live_pipe(int fd, int access, struct stat *out) {
    int flags = fcntl(fd, F_GETFL);
    return fd >= 0 && flags >= 0 && (flags & O_ACCMODE) == access &&
        fstat(fd, out) == 0 && S_ISFIFO(out->st_mode) && out->st_uid == geteuid();
}

static int original_live_channel_current(actql_bootstrap_live_channel *record) {
    if (record == NULL || record->original != record || record->process != getpid() ||
        record->retired || record->status != ACTQL_OWNED_OK)
        return ACTQL_OWNED_INVALID;
    if (record->domain == NULL || record->lease == NULL ||
        record->domain->lease != record->lease || record->domain->status != ACTQL_OWNED_OK ||
        record->domain->view == NULL || !record->domain->view->view.domain_live ||
        !record->domain->view->view.map_confirmed ||
        record->domain->view->view.mapping == NULL ||
        record->lease != (void *)((unsigned char *)record->domain->view->view.mapping +
            record->domain->view->view.payload_offset) ||
        !record->lease->extent_domain || !record->lease->fd_backed ||
        record->lease->domain_origin_pid != record->process ||
        record->lease->generation != record->domain->view->view.extent.generation ||
        record->lease->backing_device != record->domain->view->view.extent.device ||
        record->lease->backing_inode != record->domain->view->view.extent.inode ||
        record->lease->length != record->domain->view->view.payload_length ||
        memcmp(record->lease->recipe, record->domain->view->view.extent.recipe, 32) != 0) {
        record->status = ACTQL_OWNED_INVALID;
        return ACTQL_OWNED_INVALID;
    }
    struct stat left, right;
    if (!original_live_pipe(record->read_fd, O_RDONLY, &left) ||
        !original_live_pipe(record->write_fd, O_WRONLY, &right) ||
        left.st_dev != record->read_device || left.st_ino != record->read_inode ||
        right.st_dev != record->write_device || right.st_ino != record->write_inode) {
        record->status = ACTQL_OWNED_INVALID;
        return ACTQL_OWNED_INVALID;
    }
    return ACTQL_OWNED_OK;
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_capture_live_channel(
    actql_bootstrap_domain *domain, int32_t child, int32_t read_fd,
    int32_t write_fd, int64_t nonce) {
    actql_bootstrap_live_channel *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->original = record;
    record->process = getpid();
    record->domain = domain;
    record->child = (pid_t)child;
    record->read_fd = read_fd;
    record->write_fd = write_fd;
    record->nonce = nonce;
    record->status = ACTQL_OWNED_INVALID;
    struct stat left, right;
    if (domain == NULL || domain->status != ACTQL_OWNED_OK || domain->lease == NULL ||
        child <= 0 || (pid_t)child == getpid() || nonce <= 0 || read_fd == write_fd ||
        !original_live_pipe(read_fd, O_RDONLY, &left) ||
        !original_live_pipe(write_fd, O_WRONLY, &right) ||
        (left.st_dev == right.st_dev && left.st_ino == right.st_ino))
        return record;
    record->lease = domain->lease;
    record->read_device = left.st_dev;
    record->read_inode = left.st_ino;
    record->write_device = right.st_dev;
    record->write_inode = right.st_ino;
    record->status = ACTQL_OWNED_OK;
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_live_channel_status(
    actql_bootstrap_live_channel *record) {
    return original_live_channel_current(record);
}

/* Called only by the same private channel after the original child's Core
 * observation. This verifies physical correlation/bounds, not Guest identity
 * or an allocator-table grant. The trusted caller retains the actual frame. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_bind_live_span(
    actql_bootstrap_live_channel *record, int64_t nonce, int64_t offset, int64_t bytes) {
    int status = original_live_channel_current(record);
    if (status != ACTQL_OWNED_OK) return status;
    if (record->binding_attempted) return ACTQL_OWNED_INVALID;
    record->binding_attempted = true;
    if (nonce != record->nonce || offset <= 0 || bytes <= 0 ||
        (uint64_t)offset > SIZE_MAX || (uint64_t)bytes > SIZE_MAX ||
        (uint64_t)offset > record->domain->view->view.payload_length ||
        (uint64_t)bytes > record->domain->view->view.payload_length - (size_t)offset ||
        !record->lease->extent_domain || !record->lease->transferred ||
        record->lease->domain_origin_pid != record->process ||
        atomic_load_explicit(&record->lease->domain_borrower_pid, memory_order_acquire)
            != (int)record->child)
        return ACTQL_OWNED_INVALID;
    record->span_offset = (size_t)offset;
    record->span_bytes = (size_t)bytes;
    record->bound = true;
    return ACTQL_OWNED_OK;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_live_vm_current(
    actql_bootstrap_live_channel *record) {
    int status = original_live_channel_current(record);
    if (status != ACTQL_OWNED_OK) return status;
    if (!record->bound || !record->lease->extent_domain || !record->lease->transferred ||
        record->lease->domain_origin_pid != record->process ||
        atomic_load_explicit(&record->lease->domain_borrower_pid, memory_order_acquire)
            != (int)record->child)
        return ACTQL_OWNED_BUSY;
    return ACTQL_OWNED_OK;
}

/* Immutable coverage of this same bound holding, not unused allocator space.
 * The Host component includes the original control prefix and every non-VM
 * byte. It is baseline reservation DATA only, not a suballocation grant for
 * another heap, process, descriptor or physical copy. */
MOONBIT_FFI_EXPORT int64_t actql_bootstrap_live_baseline_bytes(
    actql_bootstrap_live_channel *record, int32_t ordinal) {
    if (actql_bootstrap_live_vm_current(record) != ACTQL_OWNED_OK ||
        record->span_bytes > INT64_MAX || record->lease->length > INT64_MAX ||
        record->span_bytes == 0 || record->span_bytes >= record->lease->length)
        return -1;
    if (ordinal == 0) return (int64_t)record->span_bytes;
    if (ordinal == 1) return (int64_t)(record->lease->length - record->span_bytes);
    return -1;
}

/* Metadata retirement AFTER the existing caller's separate physical ACKs.
 * This never closes a descriptor, stops a child or returns a resource loan. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_retire_live_channel_metadata(
    actql_bootstrap_live_channel *record) {
    if (record == NULL || record->original != record || record->process != getpid())
        return ACTQL_OWNED_INVALID;
    record->retired = true;
    return ACTQL_OWNED_OK;
}
