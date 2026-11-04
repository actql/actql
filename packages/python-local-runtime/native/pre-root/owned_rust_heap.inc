/* Rust-only storage inside this original holding. The existing lock protects
 * all lists, tokens and page retirement; no external heap/index is used.
 * GlobalAlloc's last-alias rule remains the caller's unsafe obligation. These
 * pages cannot be exported through the generic span/protection/lending APIs. */
/* Only pages with a free slot are listed, using original page indices. */
static void rust_unlist(actql_owned_capacity *lease, size_t index, size_t class) {
    struct rust_heap_page *page = rust_page(lease, index);
    if (page->previous != 0) rust_page(lease, page->previous)->next = page->next;
    else lease->rust_available[class] = page->next;
    if (page->next != 0) rust_page(lease, page->next)->previous = page->previous;
    page->previous = page->next = 0;
}

static void rust_list(actql_owned_capacity *lease, size_t index, size_t class) {
    struct rust_heap_page *page = rust_page(lease, index);
    page->previous = 0;
    page->next = lease->rust_available[class];
    if (page->next != 0) rust_page(lease, page->next)->previous = index;
    lease->rust_available[class] = index;
}

int actql_native_owned_rust_allocate(actql_owned_capacity *lease, size_t bytes,
    size_t alignment, void **out, uint64_t *token) {
    if (lease == NULL || out == NULL || *out != NULL || token == NULL || *token != 0 ||
        bytes == 0 || bytes > PTRDIFF_MAX || alignment == 0 ||
        (alignment & (alignment - 1)) != 0 || current_capacity != lease ||
        current_process != getpid()) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease) || lease->closing || !lease->transferred ||
        (atomic_load_explicit(&lease->rust_process, memory_order_relaxed) != 0 &&
         atomic_load_explicit(&lease->rust_process, memory_order_relaxed) != getpid()))
        goto done;
    if (lease->rust_serial == UINT64_MAX) { status = ACTQL_OWNED_EXHAUSTED; goto done; }
    atomic_store_explicit(&lease->rust_process, getpid(), memory_order_release);
    size_t class = 0, slot_bytes = 64;
    while (class < RUST_HEAP_CLASSES && (slot_bytes < bytes || slot_bytes < alignment)) {
        slot_bytes *= 2;
        class++;
    }
    void *memory = NULL;
    if (class == RUST_HEAP_CLASSES || slot_bytes > lease->page_size / 2) {
        status = allocate_locked(lease, bytes, alignment, &memory);
        if (status != ACTQL_OWNED_OK) goto done;
        size_t index = ((uintptr_t)memory - (uintptr_t)lease) / lease->page_size;
        lease->extents[index].rust_class = RUST_HEAP_LARGE;
        lease->extents[index].rust_token = ++lease->rust_serial;
        *token = lease->rust_serial;
        *out = memory;
        goto done;
    }
    size_t index = lease->rust_available[class];
    if (index == 0) {
        size_t offset = (sizeof(struct rust_heap_page) + slot_bytes - 1) & ~(slot_bytes - 1);
        if (offset >= lease->page_size || (lease->page_size - offset) / slot_bytes > RUST_HEAP_SLOTS)
            goto done;
        status = allocate_locked(lease, lease->page_size, lease->page_size, &memory);
        if (status != ACTQL_OWNED_OK) goto done;
        index = ((uintptr_t)memory - (uintptr_t)lease) / lease->page_size;
        lease->extents[index].rust_class = (unsigned char)(class + 1);
        struct rust_heap_page *page = memory;
        page->slot_bytes = slot_bytes;
        page->offset = offset;
        page->count = (lease->page_size - offset) / slot_bytes;
        rust_list(lease, index, class);
    }
    struct rust_heap_page *page = rust_page(lease, index);
    status = ACTQL_OWNED_INVALID;
    size_t slot = 0;
    while (slot < page->count && page->tokens[slot] != 0) slot++;
    if (slot == page->count) goto done; /* Never substitute another provider. */
    page->tokens[slot] = ++lease->rust_serial;
    page->live++;
    if (page->live == page->count) rust_unlist(lease, index, class);
    *out = (unsigned char *)page + page->offset + slot * page->slot_bytes;
    memset(*out, 0, page->slot_bytes);
    *token = page->tokens[slot];
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(lease);
    return status;
}

int actql_native_owned_rust_retire(actql_owned_capacity *lease, void *allocation,
                                   uint64_t token) {
    if (lease == NULL || allocation == NULL || token == 0) return ACTQL_OWNED_INVALID;
    /* Reject an inherited lock before touching it. A pointer/serial does not
     * re-adopt the original process, region or holding. */
    if (atomic_load_explicit(&lease->rust_process, memory_order_acquire) != getpid())
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    uintptr_t base = (uintptr_t)lease, address = (uintptr_t)allocation;
    if (foreign_domain_process(lease) || address < base || address - base >= lease->length)
        goto done;
    size_t index = (address - base) / lease->page_size;
    if (index < lease->control_pages) goto done;
    struct extent *extent = &lease->extents[index];
    if (extent->retired || extent->pages == 0 || extent->pages == SIZE_MAX) goto done;
    if (extent->rust_class == RUST_HEAP_LARGE) {
        if ((address - base) % lease->page_size != 0 || extent->rust_token != token) goto done;
        extent->retired = true;
        status = clean_retired(lease, index);
        goto done;
    }
    if (extent->rust_class == 0 || extent->rust_class > RUST_HEAP_CLASSES || extent->pages != 1)
        goto done;
    struct rust_heap_page *page = rust_page(lease, index);
    size_t offset = address - (uintptr_t)page;
    if (offset < page->offset || (offset - page->offset) % page->slot_bytes != 0) goto done;
    size_t slot = (offset - page->offset) / page->slot_bytes;
    if (slot >= page->count || page->tokens[slot] != token || page->live == 0) goto done;
    bool full = page->live == page->count;
    page->tokens[slot] = 0;
    page->live--;
    status = ACTQL_OWNED_OK;
    if (page->live == 0) {
        if (!full) rust_unlist(lease, index, extent->rust_class - 1);
        /* Remove from reuse before physical retirement. On failure, the same
         * extent stays retired and final original holding cleanup retries it. */
        extent->retired = true;
        status = clean_retired(lease, index);
    } else if (full) rust_list(lease, index, extent->rust_class - 1);
done:
    unlock_capacity(lease);
    return status;
}


int actql_native_owned_contains_live_rust_span(actql_owned_capacity *lease,
                                               const void *address, size_t bytes) {
    if (lease == NULL || address == NULL || bytes == 0 ||
        current_capacity != lease || current_process != getpid() ||
        atomic_load_explicit(&lease->rust_process, memory_order_acquire) != getpid())
        return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    int status = ACTQL_OWNED_INVALID;
    uintptr_t base = (uintptr_t)lease, pointer = (uintptr_t)address;
    if (foreign_domain_process(lease) || !lease->transferred || lease->closing ||
        pointer < base || pointer - base >= lease->length ||
        bytes > lease->length - (pointer - base)) goto done;
    size_t index = (pointer - base) / lease->page_size;
    if (index < lease->control_pages) goto done;
    while (index > lease->control_pages && lease->extents[index].pages == SIZE_MAX)
        index--;
    struct extent *extent = &lease->extents[index];
    if (extent->pages == 0 || extent->pages == SIZE_MAX || extent->retired ||
        extent->pages > lease->page_count - index) goto done;
    uintptr_t begin = base + index * lease->page_size;
    if (extent->rust_class == RUST_HEAP_LARGE) {
        if (extent->rust_token != 0 && pointer >= begin &&
            pointer - begin < extent->pages * lease->page_size &&
            bytes <= extent->pages * lease->page_size - (pointer - begin))
            status = ACTQL_OWNED_OK;
        goto done;
    }
    if (extent->rust_class == 0 || extent->rust_class > RUST_HEAP_CLASSES || extent->pages != 1)
        goto done;
    struct rust_heap_page *page = rust_page(lease, index);
    if (page->slot_bytes != (size_t)64 << (extent->rust_class - 1) ||
        page->offset < sizeof(struct rust_heap_page) || page->offset > lease->page_size ||
        page->count > RUST_HEAP_SLOTS ||
        page->count != (lease->page_size - page->offset) / page->slot_bytes ||
        pointer < begin + page->offset) goto done;
    size_t relative = pointer - begin - page->offset;
    size_t slot = relative / page->slot_bytes;
    if (slot < page->count && page->tokens[slot] != 0 &&
        bytes <= page->slot_bytes - relative % page->slot_bytes)
        status = ACTQL_OWNED_OK;
done:
    unlock_capacity(lease);
    return status;
}
