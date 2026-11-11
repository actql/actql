/* One shared physical record layout and census for this SAME provider.
 * No allocator, capacity grant or cleanup acknowledgement is issued here.
 * Rust-specific rows are observed from real records, never invented zeros. */
#define RUST_HEAP_CLASSES 8
#define RUST_HEAP_SLOTS 256
#define RUST_HEAP_LARGE 255
struct rust_heap_page {
    size_t previous;
    size_t next;
    size_t slot_bytes;
    size_t offset;
    size_t count;
    size_t live;
    uint64_t tokens[RUST_HEAP_SLOTS];
};

static struct rust_heap_page *rust_page(actql_owned_capacity *lease, size_t index) {
    return owned_page_address(lease, index);
}

int actql_native_owned_inventory(actql_owned_capacity *lease, uint64_t *out,
                                  size_t count) {
    if (lease == NULL || out == NULL || count != 16 ||
        current_capacity != lease || current_process != getpid())
        return ACTQL_OWNED_INVALID;
    for (size_t i = 0; i < count; i++)
        if (out[i] != 0) return ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease)) return ACTQL_OWNED_BUSY;
    lock_capacity(lease);
    uint64_t values[16] = {0};
    int status = ACTQL_OWNED_INVALID;
    if (foreign_domain_process(lease) || !lease->transferred ||
        lease->occupied_pages > lease->peak_occupied_pages ||
        lease->occupied_pages > lease->page_count) goto done;
    values[0] = lease->length;
    values[1] = lease->page_size;
    values[2] = owned_control_pages(lease) * lease->page_size;
    values[3] = lease->occupied_pages * lease->page_size;
    values[4] = lease->peak_occupied_pages * lease->page_size;
    size_t observed = owned_control_pages(lease);
    for (size_t i = lease->control_pages; i < lease->page_count;) {
        if (owned_control_page(lease, i)) { i++; continue; }
        struct extent *extent = owned_extent(lease, i);
        size_t pages = extent->pages;
        if (pages == 0) { i++; continue; }
        if (pages == SIZE_MAX || pages > lease->page_count - i) goto done;
        for (size_t j = 1; j < pages; j++)
            if (owned_extent(lease, i + j)->pages != SIZE_MAX) goto done;
        size_t bytes = pages * lease->page_size;
        observed += pages;
        if (extent->retired) {
            /* No payload access after a failed or unconfirmed protection. */
            values[11] += bytes;
        } else if (extent->rust_class == 0) {
            values[5] += bytes; values[12]++;
        } else if (extent->rust_class == RUST_HEAP_LARGE) {
            values[7] += bytes; values[13]++;
        } else if (extent->rust_class <= RUST_HEAP_CLASSES && pages == 1) {
            struct rust_heap_page *page = rust_page(lease, i);
            if (page->slot_bytes != (size_t)64 << (extent->rust_class - 1) ||
                page->offset > lease->page_size || page->count > RUST_HEAP_SLOTS ||
                page->count != (lease->page_size - page->offset) / page->slot_bytes ||
                page->live > page->count) goto done;
            values[6] += bytes; values[14]++;
            values[8] += sizeof(struct rust_heap_page);
            values[9] += page->live * page->slot_bytes;
            values[10] += (page->count - page->live) * page->slot_bytes;
            values[15] += page->live;
        } else goto done;
        i += pages;
    }
    if (observed != lease->occupied_pages) goto done;
    memcpy(out, values, sizeof(values));
    status = ACTQL_OWNED_OK;
done:
    unlock_capacity(lease);
    return status;
}
