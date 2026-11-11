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
    lease->page_count = lease->original_page_count = count;
    lease->control_pages = control_pages;
    lease->first_free_page = control_pages;
    lease->occupied_pages = lease->peak_occupied_pages = control_pages;
    lease->allocation_ceiling_pages = count;
    lease->allocation_maximum_pages = count;
    lease->backing_device = (uint64_t)before.st_dev;
    lease->backing_inode = (uint64_t)before.st_ino;
    lease->fd_backed = true;
    lease->extent_domain = false;
    atomic_init(&lease->domain_borrower_pid, 0);
    atomic_init(&lease->rust_process, 0);
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
    if (owner == NULL) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    /* The existing caller excludes concurrent original close/retirement. */
    size_t start;
    lock_capacity(owner);
    bool original = allocation_start(owner, allocation, &start);
    size_t length = original ? owned_extent(owner, start)->pages * owner->page_size : 0;
    unlock_capacity(owner);
    if (!original) return ACTQL_OWNED_INVALID;
    return actql_native_owned_lend_extent_range(owner, allocation, 0, length, writable, loan);
}

static int lend_extent_range_locked(actql_owned_capacity *owner, void *allocation,
    size_t offset, size_t length, bool writable, actql_owned_extent_loan *loan,
    bool in_process, bool domain_storage) {
    size_t start;
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(owner) || (in_process ? owner->fd_backed : !owner->fd_backed) || !owner->transferred || owner->closing ||
        !allocation_start(owner, allocation, &start) || owned_extent(owner, start)->retired)
        goto done;
    struct extent *extent = owned_extent(owner, start);
    size_t allocation_bytes = extent->pages * owner->page_size;
    if (extent->domain_storage != domain_storage ||
        (domain_storage && (!in_process || !writable || offset != 0 ||
                            length != allocation_bytes))) goto done;
    if (offset > allocation_bytes || length > allocation_bytes - offset) goto done;
    if (writable && extent->sealed) {
        status = ACTQL_OWNED_BUSY;
        goto done;
    }
    start += offset / owner->page_size;
    size_t pages = length / owner->page_size;
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = owned_extent(owner, start + i);
        if (page->external_writer ||
            (writable && page->external_readers != 0) ||
            (!writable && page->external_readers == SIZE_MAX)) {
            status = ACTQL_OWNED_BUSY;
            goto done;
        }
    }
    loan->original = loan;
    loan->owner = owner;
    loan->start = start;
    loan->extent = (actql_owned_extent_reference){
        .device = owner->backing_device, .inode = owner->backing_inode,
        .generation = owner->generation, .capacity = owner->length,
        .offset = start * owner->page_size,
        .length = length, .writable = writable
    };
    memcpy(loan->extent.recipe, owner->recipe, sizeof(owner->recipe));
    loan->returned = false;
    loan->local_process = in_process ? (int64_t)getpid() : 0;
    loan->domain_storage = domain_storage;
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = owned_extent(owner, start + i);
        if (writable) page->external_writer = true;
        else page->external_readers++;
    }
    status = ACTQL_OWNED_OK;
done:
    return status;
}

static int lend_extent_range(actql_owned_capacity *owner, void *allocation,
                                        size_t offset, size_t length, bool writable,
                                        actql_owned_extent_loan *loan, bool in_process,
                                        bool domain_storage) {
    if (owner == NULL || loan == NULL || loan->original != NULL ||
        actql_native_owned_current() != owner || length == 0 ||
        (in_process && !writable) ||
        offset % owner->page_size != 0 || length % owner->page_size != 0)
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    lock_capacity(owner);
    int status = owner->pending_growth_domain != NULL ? ACTQL_OWNED_BUSY :
        lend_extent_range_locked(owner, allocation, offset, length, writable,
                                 loan, in_process, domain_storage);
    unlock_capacity(owner);
    return status;
}

int actql_native_owned_lend_extent_range(actql_owned_capacity *owner, void *allocation,
    size_t offset, size_t length, bool writable, actql_owned_extent_loan *loan) {
    return lend_extent_range(owner, allocation, offset, length, writable, loan, false, false);
}

int actql_native_owned_lend_in_process_extent_range(actql_owned_capacity *owner,
    void *allocation, size_t offset, size_t length, bool writable,
    actql_owned_extent_loan *loan) {
    return lend_extent_range(owner, allocation, offset, length, writable, loan, true, false);
}

int actql_native_owned_allocate_in_process_domain(actql_owned_capacity *owner,
    size_t bytes, void **out) {
    if (owner == NULL || out == NULL || *out != NULL || current_capacity != owner ||
        current_process != getpid()) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    lock_capacity(owner);
    int status = ACTQL_OWNED_INVALID;
    if (!foreign_domain_process(owner) && !owner->fd_backed && owner->transferred &&
        !owner->closing)
        status = allocate_storage_locked(owner, bytes, owner->page_size, out, true);
    unlock_capacity(owner);
    return status;
}

int actql_native_owned_lend_in_process_domain(actql_owned_capacity *owner,
    void *allocation, size_t bytes, actql_owned_extent_loan *loan) {
    return lend_extent_range(owner, allocation, 0, bytes, true, loan, true, true);
}

static bool local_view_original(const actql_owned_extent_view *view) {
    const actql_owned_extent_loan *loan = view->local_loan;
    return loan != NULL && loan->original == loan && !loan->returned &&
        loan->local_process == (int64_t)getpid() && loan->local_view_live &&
        view->original == view && view->mapping ==
            owned_page_address(loan->owner, loan->start) &&
        view->length == loan->extent.length && view->domain_storage == loan->domain_storage &&
        memcmp(&view->extent, &loan->extent, sizeof(view->extent)) == 0;
}

static int view_in_process_extent_locked(actql_owned_extent_loan *loan,
    size_t payload_offset, size_t payload_length, actql_owned_extent_view *view,
    bool domain_storage) {
    if (loan == NULL || loan->original != loan || loan->returned ||
        loan->local_process != (int64_t)getpid() || !loan->extent.writable || view == NULL ||
        view->original != NULL || payload_length == 0 ||
        payload_offset > loan->extent.length ||
        payload_length > loan->extent.length - payload_offset ||
        loan->domain_storage != domain_storage ||
        (domain_storage && (payload_offset != 0 || payload_length != loan->extent.length)))
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    int status = ACTQL_OWNED_BUSY;
    if (!owner->closing && !owner->fd_backed && !loan->local_view_attempted) {
        loan->local_view_attempted = true;
        loan->local_view_live = true;
        view->original = view;
        view->local_loan = loan;
        view->mapping = owned_page_address(owner, loan->start);
        view->length = loan->extent.length;
        view->extent = loan->extent;
        view->payload_offset = payload_offset;
        view->payload_length = payload_length;
        view->payload_bound = true;
        view->map_confirmed = true;
        view->domain_storage = domain_storage;
        status = ACTQL_OWNED_OK;
    }
    return status;
}

static int view_in_process_extent(actql_owned_extent_loan *loan,
    size_t payload_offset, size_t payload_length, actql_owned_extent_view *view,
    bool domain_storage) {
    if (loan == NULL || loan->original != loan || loan->returned ||
        (loan->local_process != 0 && loan->local_process != (int64_t)getpid()) ||
        loan->owner == NULL) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    lock_capacity(owner);
    int status = owner->pending_growth_domain != NULL ? ACTQL_OWNED_BUSY :
        view_in_process_extent_locked(loan, payload_offset, payload_length, view, domain_storage);
    unlock_capacity(owner);
    return status;
}

int actql_native_owned_view_in_process_extent(actql_owned_extent_loan *loan,
    size_t payload_offset, size_t payload_length, actql_owned_extent_view *view) {
    return view_in_process_extent(loan, payload_offset, payload_length, view, false);
}

int actql_native_owned_view_in_process_domain(actql_owned_extent_loan *loan,
    actql_owned_extent_view *view) {
    if (loan == NULL) return ACTQL_OWNED_INVALID;
    return view_in_process_extent(loan, 0, loan->extent.length, view, true);
}

int actql_native_owned_project_extent(actql_owned_extent_loan *loan,
                                     actql_owned_extent_reference *out) {
    if (loan == NULL || loan->original != loan || loan->returned || loan->local_process != 0 || out == NULL)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
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
    if (!header->fd_backed || header->extent_domain || header->closing || header->length != extent->capacity ||
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
    view->extent = *extent;
    view->map_confirmed = false;
    struct stat after;
    if (!region_fd_identity(fd, extent->capacity, &after) || before.st_dev != after.st_dev ||
        before.st_ino != after.st_ino) return ACTQL_OWNED_PHYSICAL_FAILURE;
    view->map_confirmed = true;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_close_extent_view(actql_owned_extent_view *view) {
    if (view == NULL || view->original != view) return ACTQL_OWNED_INVALID;
    if (view->mapping == NULL) return ACTQL_OWNED_OK;
    if (view->domain_live) return ACTQL_OWNED_BUSY;
    if (view->local_loan != NULL) {
        if (!local_view_original(view)) return ACTQL_OWNED_INVALID;
        view->local_loan->local_view_live = false;
        view->mapping = NULL;
        return ACTQL_OWNED_OK;
    }
    if (munmap(view->mapping, view->length) != 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    view->mapping = NULL;
    return ACTQL_OWNED_OK;
}

static int return_extent_locked(actql_owned_extent_loan *loan) {
    if (loan == NULL || loan->original != loan || loan->returned)
        return ACTQL_OWNED_INVALID;
    if (loan->local_process != 0 && loan->local_process != (int64_t)getpid())
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    if (loan->local_view_live) {
        return ACTQL_OWNED_BUSY;
    }
    size_t pages = loan->extent.length / owner->page_size;
    int status = ACTQL_OWNED_INVALID;
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = owned_extent(owner, loan->start + i);
        if (!(loan->extent.writable ? page->external_writer : page->external_readers != 0))
            goto done;
    }
    for (size_t i = 0; i < pages; i++) {
        struct extent *page = owned_extent(owner, loan->start + i);
        if (loan->extent.writable) page->external_writer = false;
        else page->external_readers--;
    }
    loan->returned = true;
    status = ACTQL_OWNED_OK;
done:
    return status;
}

int actql_native_owned_return_extent(actql_owned_extent_loan *loan) {
    if (loan == NULL || loan->original != loan || loan->returned ||
        (loan->local_process != 0 && loan->local_process != (int64_t)getpid()) ||
        loan->owner == NULL) return ACTQL_OWNED_INVALID;
    actql_owned_capacity *owner = loan->owner;
    if (foreign_domain_process(owner)) return ACTQL_OWNED_BUSY;
    lock_capacity(owner);
    int status = return_extent_locked(loan);
    unlock_capacity(owner);
    return status;
}


int actql_native_owned_map_extent_payload(int fd,
    const actql_owned_extent_reference *extent, size_t payload_offset,
    size_t payload_length, actql_owned_extent_view *view) {
    if (extent == NULL || view == NULL || view->original != NULL ||
        payload_length == 0 || payload_offset > extent->length ||
        payload_length > extent->length - payload_offset)
        return ACTQL_OWNED_INVALID;
    int status = actql_native_owned_map_extent(fd, extent, view);
    /* Preserve the same post-map partial view; a failed map is never funding. */
    if (view->original == view) {
        view->payload_offset = payload_offset;
        view->payload_length = payload_length;
        view->payload_bound = true;
    }
    return status;
}

int actql_native_owned_acquire_extent_domain(actql_owned_extent_view *view,
                                            actql_owned_capacity **out) {
    if (out == NULL || *out != NULL || view == NULL || view->original != view ||
        view->mapping == NULL || !view->map_confirmed || !view->payload_bound ||
        !view->extent.writable || view->domain_attempted || view->domain_live)
        return ACTQL_OWNED_INVALID;
    if (view->local_loan != NULL && !local_view_original(view))
        return ACTQL_OWNED_INVALID;
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    size_t page = (size_t)selected_page;
    size_t bytes = view->payload_length;
    if (view->payload_offset % page != 0 || bytes % page != 0 || bytes == 0 ||
        bytes > PTRDIFF_MAX || view->payload_offset > view->length ||
        bytes > view->length - view->payload_offset)
        return ACTQL_OWNED_INVALID;
    size_t count = bytes / page;
    if (count > (SIZE_MAX - sizeof(actql_owned_capacity)) / sizeof(struct extent))
        return ACTQL_OWNED_INVALID;
    size_t control_pages;
    if (!round_pages(sizeof(actql_owned_capacity) + count * sizeof(struct extent),
                     page, &control_pages) || control_pages >= count)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = (void *)((unsigned char *)view->mapping + view->payload_offset);
    /* An old initialized payload is not a new original supplier. Never reset
     * a dead child's control records or recreate its unused allowances. */
    const unsigned char *header = (const unsigned char *)lease;
    for (size_t i = 0; i < sizeof(*lease); i++)
        if (header[i] != 0) return ACTQL_OWNED_IMAGE_MISMATCH;
    view->domain_attempted = true;
    view->domain_live = true;
    *out = lease;
    /* Private local registration already cleared this exact control prefix.
     * The untouched payload has never been a generic span or view. Child
     * allocate_locked still clears every byte before publishing an allocation. */
    if (!view->domain_storage) memset(lease, 0, control_pages * page);
    lease->length = bytes;
    lease->page_size = page;
    lease->page_count = lease->original_page_count = count;
    lease->control_pages = control_pages;
    lease->first_free_page = control_pages;
    lease->occupied_pages = lease->peak_occupied_pages = control_pages;
    lease->allocation_ceiling_pages = count;
    lease->allocation_maximum_pages = count;
    lease->backing_device = view->extent.device;
    lease->backing_inode = view->extent.inode;
    lease->fd_backed = view->local_loan == NULL;
    lease->extent_domain = true;
    lease->domain_origin_pid = getpid();
    atomic_init(&lease->domain_borrower_pid, 0);
    atomic_init(&lease->rust_process, 0);
    lease->generation = view->extent.generation;
    memcpy(lease->recipe, view->extent.recipe, sizeof(lease->recipe));
    lease->lock = (atomic_flag)ATOMIC_FLAG_INIT;
    return ACTQL_OWNED_OK;
}


/* Both locks are held, parent before child. The original Common carrier keeps
 * these caller-funded nominal objects alive and excludes competing close of
 * their views. Scalar bounds or an equal recipe never replace those originals. */
static bool whole_local_domain_view(actql_owned_extent_view *view,
                                    actql_owned_capacity *parent) {
    if (!local_view_original(view) || view->local_loan->owner != parent ||
        !view->map_confirmed || !view->payload_bound || !view->domain_storage ||
        !view->extent.writable || view->domain_borrowed || view->payload_offset != 0 ||
        view->payload_length != view->length || view->length % parent->page_size != 0 ||
        view->extent.generation != parent->generation ||
        memcmp(view->extent.recipe, parent->recipe, sizeof(parent->recipe)) != 0)
        return false;
    size_t start;
    if (!allocation_start(parent, view->mapping, &start) ||
        start != view->local_loan->start) return false;
    struct extent *extent = owned_extent(parent, start);
    if (extent->retired || !extent->domain_storage ||
        extent->pages * parent->page_size != view->length) return false;
    for (size_t i = 0; i < extent->pages; i++)
        if (!owned_extent(parent, start + i)->external_writer) return false;
    return true;
}

static int attach_domain_segment_locked(actql_owned_capacity *domain,
    actql_owned_extent_view *original_view, actql_owned_extent_view *addition_view,
    size_t expected_domain_bytes, uint64_t *control_bytes, bool preserve_ceiling,
    size_t acquired_bound_pages) {
    actql_owned_capacity *parent = original_view->local_loan->owner;
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(parent) || foreign_domain_process(domain) ||
        parent->closing || domain->closing) {
        status = ACTQL_OWNED_BUSY;
        goto done;
    }
    if (!parent->transferred || parent->fd_backed || !domain->transferred ||
        domain->fd_backed || !domain->extent_domain || domain->domain_borrow_attempted ||
        (domain->allocation_ceiling_attempted && !preserve_ceiling) ||
        atomic_load_explicit(&domain->domain_borrower_pid, memory_order_acquire) != 0 ||
        actql_native_owned_domain_matches_view(domain, original_view, getpid()) != ACTQL_OWNED_OK ||
        !whole_local_domain_view(original_view, parent) ||
        !whole_local_domain_view(addition_view, parent) ||
        addition_view->domain_attempted || addition_view->domain_live ||
        expected_domain_bytes != domain->length ||
        addition_view->length > PTRDIFF_MAX - domain->length)
        goto done;
    size_t count, controls;
    if (!owned_growth_layout(domain, addition_view->length, &count, &controls)) goto done;
    /* Only the checked Read supplier can extend a bound, by this exact
     * already-acquired addition. No requested cap or logical byte deficit is
     * copied here. Bare attach and ordinary checked growth still keep it. */
    if (acquired_bound_pages != 0 &&
        (acquired_bound_pages != count || !domain->allocation_working_bound)) goto done;
    if (acquired_bound_pages > SIZE_MAX - domain->allocation_ceiling_pages) goto done;
    size_t ceiling = domain->allocation_ceiling_pages + acquired_bound_pages;
    if (domain->allocation_ceiling_attempted && ceiling > domain->allocation_maximum_pages)
        ceiling = domain->allocation_maximum_pages;
    if (domain->allocation_ceiling_attempted &&
        (domain->occupied_pages > ceiling ||
         controls > ceiling - domain->occupied_pages)) {
        status = ACTQL_OWNED_EXHAUSTED;
        goto done;
    }
    struct owned_segment *segment = addition_view->mapping;
    /* The exact private parent allocation already funds the added controls.
     * No fallible operation remains after this clear and atomic publication. */
    memset(segment, 0, controls * domain->page_size);
    segment->next = domain->segments;
    segment->borrowed_view = addition_view;
    segment->first_page = domain->page_count;
    segment->page_count = count;
    segment->control_pages = controls;
    for (size_t i = 0; i < controls; i++) segment->extents[i].pages = SIZE_MAX;
    domain->segments = segment;
    domain->page_count += count;
    domain->length += addition_view->length;
    if (!domain->allocation_ceiling_attempted) {
        domain->allocation_ceiling_pages += count;
        domain->allocation_maximum_pages += count;
    } else {
        domain->allocation_ceiling_pages = ceiling;
    }
    domain->occupied_pages += controls;
    if (domain->occupied_pages > domain->peak_occupied_pages)
        domain->peak_occupied_pages = domain->occupied_pages;
    addition_view->domain_attempted = true;
    addition_view->domain_live = true;
    *control_bytes = controls * domain->page_size;
    status = ACTQL_OWNED_OK;
done:
    return status;
}

int actql_native_owned_attach_in_process_domain_segment(
    actql_owned_capacity *domain, actql_owned_extent_view *original_view,
    actql_owned_extent_view *addition_view, size_t expected_domain_bytes,
    uint64_t *control_bytes) {
    if (domain == NULL || original_view == NULL || addition_view == NULL ||
        original_view == addition_view || original_view->original != original_view ||
        addition_view->original != addition_view || original_view->local_loan == NULL ||
        addition_view->local_loan == NULL || control_bytes == NULL || *control_bytes != 0 ||
        current_capacity != domain || current_process != getpid())
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *parent = original_view->local_loan->owner;
    if (parent == NULL || parent == domain || addition_view->local_loan->owner != parent)
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(parent) || foreign_domain_process(domain))
        return ACTQL_OWNED_BUSY;
    lock_capacity(parent);
    lock_capacity(domain);
    int status = parent->pending_growth_domain != NULL ? ACTQL_OWNED_BUSY :
        attach_domain_segment_locked(domain, original_view, addition_view,
                                     expected_domain_bytes, control_bytes, false, 0);
    unlock_capacity(domain);
    unlock_capacity(parent);
    return status;
}


#include "owned_domain_growth.inc"

int actql_native_owned_close_extent_domain(actql_owned_extent_view *view,
                                          actql_owned_capacity **slot) {
    if (view == NULL || view->original != view || slot == NULL)
        return ACTQL_OWNED_INVALID;
    if (*slot == NULL) return view->domain_attempted && !view->domain_live
                                ? ACTQL_OWNED_OK : ACTQL_OWNED_INVALID;
    if (view->mapping == NULL || !view->domain_live || !view->payload_bound ||
        view->domain_borrowed ||
        *slot != (void *)((unsigned char *)view->mapping + view->payload_offset))
        return ACTQL_OWNED_INVALID;
    if (view->local_loan != NULL && !local_view_original(view))
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = *slot;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    if (!lease->extent_domain || lease->original_page_count * lease->page_size != view->payload_length ||
        lease->generation != view->extent.generation ||
        memcmp(lease->recipe, view->extent.recipe, sizeof(lease->recipe)) != 0)
        return ACTQL_OWNED_IMAGE_MISMATCH;
    /* Do not touch a child's lock, including after that child died in a call.
     * PID disappearance is not a physical return or a cleanup acknowledgment. */
    if (atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) != 0)
        return ACTQL_OWNED_BUSY;
    actql_owned_capacity *parent = lease->growth.parent;
    if (parent != NULL) lock_capacity(parent);
    lock_capacity(lease);
    if (atomic_load_explicit(&lease->domain_borrower_pid, memory_order_relaxed) != 0) {
        unlock_capacity(lease);
        if (parent != NULL) unlock_capacity(parent);
        return ACTQL_OWNED_BUSY;
    }
    int prepared = prepare_capacity_close_locked(lease);
    if (prepared != ACTQL_OWNED_OK) {
        unlock_capacity(lease);
        if (parent != NULL) unlock_capacity(parent);
        return prepared;
    }
    /* All allocations and Read aliases are retired before any additional view
     * is released. Physical storage remains exclusively lent by its original
     * parent until the separate view/loan/allocation cleanup sequence. */
    while (lease->segments != NULL) {
        struct owned_segment *segment = lease->segments;
        segment->borrowed_view->domain_live = false;
        lease->segments = segment->next;
        lease->page_count -= segment->page_count;
        lease->length -= segment->page_count * lease->page_size;
        lease->occupied_pages -= segment->control_pages;
    }
    int cleaned = cleanup_domain_growth_locked(lease);
    if (cleaned != ACTQL_OWNED_OK) {
        unlock_capacity(lease);
        if (parent != NULL) unlock_capacity(parent);
        return cleaned;
    }
    view->domain_live = false;
    *slot = NULL;
    unlock_capacity(lease);
    if (parent != NULL) unlock_capacity(parent);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_borrow_extent_domain(actql_owned_extent_view *view,
                                           actql_owned_capacity **out) {
    if (view == NULL || view->local_loan != NULL || view->original != view || out == NULL || *out != NULL ||
        view->mapping == NULL || !view->map_confirmed || !view->payload_bound ||
        !view->extent.writable || view->domain_attempted || view->domain_live)
        return ACTQL_OWNED_INVALID;
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    size_t page = (size_t)selected_page, bytes = view->payload_length;
    if (view->payload_offset % page != 0 || bytes % page != 0 || bytes == 0 ||
        bytes > PTRDIFF_MAX || view->payload_offset > view->length ||
        bytes > view->length - view->payload_offset)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = (void *)((unsigned char *)view->mapping + view->payload_offset);
    size_t count = bytes / page, control_pages;
    if (count > (SIZE_MAX - sizeof(*lease)) / sizeof(struct extent) ||
        !round_pages(sizeof(*lease) + count * sizeof(struct extent), page, &control_pages) ||
        control_pages >= count || !lease->extent_domain || !lease->fd_backed ||
        lease->length != bytes || lease->page_size != page || lease->page_count != count ||
        lease->control_pages != control_pages || lease->generation != view->extent.generation ||
        lease->backing_device != view->extent.device || lease->backing_inode != view->extent.inode ||
        memcmp(lease->recipe, view->extent.recipe, sizeof(lease->recipe)) != 0 ||
        lease->domain_origin_pid == getpid() || lease->domain_origin_pid <= 0 ||
        current_capacity != NULL ||
        atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) != 0)
        return ACTQL_OWNED_IMAGE_MISMATCH;
    lock_capacity(lease);
    if (!lease->transferred || lease->closing || lease->active_scopes != 0 ||
        lease->domain_borrow_attempted ||
        atomic_load_explicit(&lease->domain_borrower_pid, memory_order_relaxed) != 0) {
        unlock_capacity(lease);
        return ACTQL_OWNED_BUSY;
    }
    /* No header reset, allocator credit issuance, allocation or new mapping. */
    lease->domain_borrow_attempted = true;
    atomic_store_explicit(&lease->domain_borrower_pid, (int)getpid(), memory_order_release);
    view->domain_attempted = true;
    view->domain_live = true;
    view->domain_borrowed = true;
    *out = lease;
    unlock_capacity(lease);
    return ACTQL_OWNED_OK;
}

int actql_native_owned_return_extent_domain_borrow(actql_owned_extent_view *view,
                                                  actql_owned_capacity **slot) {
    if (view == NULL || view->local_loan != NULL || view->original != view || slot == NULL || !view->domain_borrowed)
        return ACTQL_OWNED_INVALID;
    if (*slot == NULL) return !view->domain_live ? ACTQL_OWNED_OK : ACTQL_OWNED_INVALID;
    if (view->mapping == NULL || !view->domain_live ||
        *slot != (void *)((unsigned char *)view->mapping + view->payload_offset))
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = *slot;
    if (atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) != (int)getpid())
        return ACTQL_OWNED_INVALID;
    lock_capacity(lease);
    int status = prepare_capacity_close_locked(lease);
    if (status == ACTQL_OWNED_OK) {
        /* Closing stays sticky. A later process cannot restart this allocator. */
        view->domain_live = false;
        *slot = NULL;
    }
    unlock_capacity(lease);
    /* Publish return only AFTER releasing the child lock. Death before this
     * store conservatively retains the borrow, never strands a parent caller
     * behind a lock whose process has already disappeared. */
    if (status == ACTQL_OWNED_OK)
        atomic_store_explicit(&lease->domain_borrower_pid, 0, memory_order_release);
    return status;
}

int actql_native_owned_unmap_stopped_child_domain(actql_owned_extent_view *view,
                                                 actql_owned_capacity **slot) {
    /* The Native process Owner must retain and validate its original scoped
     * stop proof before this physical call. Neither this port nor the recorded
     * borrower PID issues such a proof. Ordinary close/borrow return above
     * deliberately keep their allocation-level requirements unchanged. */
    if (view == NULL || view->local_loan != NULL || view->original != view || slot == NULL || *slot == NULL ||
        !view->domain_attempted || view->domain_borrowed || !view->payload_bound ||
        !view->extent.writable || current_capacity != NULL ||
        actql_native_owned_domain_matches_view(*slot, view, (int64_t)getpid()) != ACTQL_OWNED_OK)
        return ACTQL_OWNED_INVALID;
    actql_owned_capacity *lease = *slot;
    if (!lease->transferred || !lease->domain_borrow_attempted ||
        atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) <= 0)
        return ACTQL_OWNED_INVALID;
    /* Do not lock, reset or mark the child's shared allocator as returned.
     * It may retain a process-static allocation or an abandoned lock. The
     * parent loan stays pinned, including through a failed physical unmap. */
    if (munmap(view->mapping, view->length) != 0)
        return ACTQL_OWNED_PHYSICAL_FAILURE;
    view->mapping = NULL;
    view->domain_live = false;
    *slot = NULL;
    return ACTQL_OWNED_OK;
}

int actql_native_owned_domain_unborrowed(actql_owned_capacity *lease,
    const actql_owned_extent_view *view) {
    if (view == NULL || view->original != view || view->domain_borrowed ||
        current_capacity != NULL ||
        actql_native_owned_domain_matches_view(lease, view, (int64_t)getpid()) != ACTQL_OWNED_OK)
        return ACTQL_OWNED_INVALID;
    return lease->transferred && !lease->closing && !lease->domain_borrow_attempted &&
        atomic_load_explicit(&lease->domain_borrower_pid, memory_order_acquire) == 0
        ? ACTQL_OWNED_OK : ACTQL_OWNED_BUSY;
}
