#include "owned_region.h"

static bool region_fd_identity(int fd, size_t capacity, struct stat *status) {
    int flags = fcntl(fd, F_GETFL);
    return flags >= 0 && (flags & O_ACCMODE) == O_RDWR &&
           fstat(fd, status) == 0 && S_ISREG(status->st_mode) &&
           (status->st_mode & 0777) == 0600 && status->st_uid == geteuid() &&
           status->st_nlink <= 1 && status->st_size >= 0 &&
           (uint64_t)status->st_size == (uint64_t)capacity;
}

int actql_native_owned_acquire_fd(int fd, size_t capacity, uint64_t generation,
                                 const unsigned char recipe[32],
                                 actql_owned_capacity **out) {
    if (out == NULL || *out != NULL || recipe == NULL || generation == 0)
        return ACTQL_OWNED_INVALID;
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    size_t page = (size_t)selected_page;
    if (capacity == 0 || capacity > PTRDIFF_MAX || capacity % page != 0)
        return ACTQL_OWNED_INVALID;
    size_t count = capacity / page;
    if (count > (SIZE_MAX - sizeof(actql_owned_capacity)) / sizeof(struct extent))
        return ACTQL_OWNED_INVALID;
    size_t control_pages;
    if (!round_pages(sizeof(actql_owned_capacity) + count * sizeof(struct extent),
                     page, &control_pages) || control_pages >= count)
        return ACTQL_OWNED_INVALID;
    struct stat before;
    if (!region_fd_identity(fd, capacity, &before)) return ACTQL_OWNED_INVALID;
    /* Exclusive first adoption is a trusted physical supplier precondition.
     * Reject a previous initialized header instead of resetting its custody. */
    unsigned char header[sizeof(actql_owned_capacity)];
    if (pread(fd, header, sizeof(header), 0) != (ssize_t)sizeof(header))
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    for (size_t i = 0; i < sizeof(header); i++)
        if (header[i] != 0) return ACTQL_OWNED_INVALID;
    void *mapping = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) return ACTQL_OWNED_PHYSICAL_FAILURE;
    actql_owned_capacity *lease = mapping;
    /* Initialize this one provider's relative control records. No descriptor
     * owns a second allocator or another execution-byte reservation. */
    memset(lease, 0, control_pages * page);
    lease->length = capacity;
    lease->page_size = page;
    lease->page_count = count;
    lease->control_pages = control_pages;
    lease->backing_device = (uint64_t)before.st_dev;
    lease->backing_inode = (uint64_t)before.st_ino;
    lease->fd_backed = true;
    lease->generation = generation;
    memcpy(lease->recipe, recipe, sizeof(lease->recipe));
    lease->lock = (atomic_flag)ATOMIC_FLAG_INIT;
    *out = lease;
    struct stat after;
    if (!region_fd_identity(fd, capacity, &after) || before.st_dev != after.st_dev ||
        before.st_ino != after.st_ino) return ACTQL_OWNED_PHYSICAL_FAILURE;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_lend_extent(actql_owned_capacity *owner, void *allocation,
                                  bool writable, actql_owned_extent_loan *loan) {
    if (owner == NULL || loan == NULL || loan->original != NULL ||
        actql_native_owned_current() != owner) return ACTQL_OWNED_INVALID;
    lock_capacity(owner);
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (!owner->fd_backed || !owner->transferred || owner->closing ||
        !allocation_start(owner, allocation, &start) || owner->extents[start].retired)
        goto done;
    struct extent *extent = &owner->extents[start];
    if (extent->external_writer ||
        (writable && (extent->external_readers != 0 || extent->sealed)) ||
        (!writable && extent->external_readers == SIZE_MAX)) {
        status = ACTQL_OWNED_BUSY;
        goto done;
    }
    loan->original = loan;
    loan->owner = owner;
    loan->start = start;
    loan->extent = (actql_owned_extent_reference){
        .device = owner->backing_device, .inode = owner->backing_inode,
        .generation = owner->generation, .capacity = owner->length,
        .offset = start * owner->page_size,
        .length = extent->pages * owner->page_size, .writable = writable
    };
    memcpy(loan->extent.recipe, owner->recipe, sizeof(owner->recipe));
    loan->returned = false;
    if (writable) extent->external_writer = true;
    else extent->external_readers++;
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(owner);
    return status;
}

int actql_native_owned_project_extent(actql_owned_extent_loan *loan,
                                     actql_owned_extent_reference *out) {
    if (loan == NULL || loan->original != loan || loan->returned || out == NULL)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    lock_capacity(owner);
    int status = ACTQL_OWNED_BUSY;
    if (!owner->closing) {
        *out = loan->extent;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(owner);
    return status;
}

int actql_native_owned_map_extent(int fd, const actql_owned_extent_reference *extent,
                                 actql_owned_extent_view *view) {
    if (extent == NULL || view == NULL || view->original != NULL ||
        extent->capacity > PTRDIFF_MAX || extent->length == 0)
        return ACTQL_OWNED_INVALID;
    struct stat before;
    if (!region_fd_identity(fd, extent->capacity, &before) ||
        (uint64_t)before.st_dev != extent->device ||
        (uint64_t)before.st_ino != extent->inode) return ACTQL_OWNED_IMAGE_MISMATCH;
    /* Read only immutable original layout. The child never maps or acquires
     * the parent's control lock; process death cannot strand that lock. */
    actql_owned_capacity original_header;
    if (pread(fd, &original_header, sizeof(original_header), 0) != (ssize_t)sizeof(original_header))
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    const actql_owned_capacity *header = &original_header;
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    size_t page = (size_t)selected_page;
    if (!header->fd_backed || header->closing || header->length != extent->capacity ||
        header->page_size != page || header->generation != extent->generation ||
        header->backing_device != extent->device || header->backing_inode != extent->inode ||
        memcmp(header->recipe, extent->recipe, sizeof(header->recipe)) != 0 ||
        header->control_pages > extent->capacity / page ||
        extent->offset < header->control_pages * page ||
        extent->offset % page != 0 || extent->length % page != 0 ||
        extent->offset > extent->capacity || extent->length > extent->capacity - extent->offset)
        return ACTQL_OWNED_IMAGE_MISMATCH;
    int protection = PROT_READ | (extent->writable ? PROT_WRITE : 0);
    void *mapping = mmap(NULL, extent->length, protection, MAP_SHARED, fd, (off_t)extent->offset);
    if (mapping == MAP_FAILED) return ACTQL_OWNED_PHYSICAL_FAILURE;
    view->original = view;
    view->mapping = mapping;
    view->length = extent->length;
    struct stat after;
    if (!region_fd_identity(fd, extent->capacity, &after) || before.st_dev != after.st_dev ||
        before.st_ino != after.st_ino) return ACTQL_OWNED_PHYSICAL_FAILURE;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_close_extent_view(actql_owned_extent_view *view) {
    if (view == NULL || view->original != view) return ACTQL_OWNED_INVALID;
    if (view->mapping == NULL) return ACTQL_OWNED_OK;
    if (munmap(view->mapping, view->length) != 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    view->mapping = NULL;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_return_extent(actql_owned_extent_loan *loan) {
    if (loan == NULL || loan->original != loan || loan->returned)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    lock_capacity(owner);
    struct extent *extent = &owner->extents[loan->start];
    int status = ACTQL_OWNED_INVALID;
    if (loan->extent.writable ? extent->external_writer : extent->external_readers != 0) {
        if (loan->extent.writable) extent->external_writer = false;
        else extent->external_readers--;
        loan->returned = true;
        status = ACTQL_OWNED_OK;
    }
    unlock_capacity(owner);
    return status;
}
