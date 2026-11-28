/* Allocation mechanics shared by the existing Native Read and portable Crypto owners. */
static size_t rounded(size_t n) {
    if (n > SIZE_MAX - (alignment - 1)) return 0;
    return (n + alignment - 1) & ~(alignment - 1);
}
static size_t header_bytes(void) { return rounded(sizeof(block)); }
static void *payload(block *b) { return (unsigned char *)b + header_bytes(); }
static block *next_block(block *b) {
    unsigned char *next = (unsigned char *)payload(b) + b->available;
    unsigned char *end = (unsigned char *)state + state->bytes;
    return next == end ? NULL : (block *)next;
}
/* One bit per aligned position, inside the same extent. Only an exact live
 * payload start has a bit. Classify integers and this original metadata before
 * accessing any header; foreign/interior/retired pointers are never probed. */
static void mark_start(block *b, int live) {
    size_t index = ((uintptr_t)payload(b) - (uintptr_t)state) / alignment;
    unsigned char mask = (unsigned char)(1u << (index % 8));
    if (live) state->live_starts[index / 8] |= mask;
    else state->live_starts[index / 8] &= (unsigned char)~mask;
}
static block *find(void *p) {
    uintptr_t value = (uintptr_t)p, base = (uintptr_t)state;
    if (value < (uintptr_t)payload(state->first) || value - base >= state->bytes ||
        (value - base) % alignment) return NULL;
    size_t index = (value - base) / alignment;
    if (!(state->live_starts[index / 8] & (1u << (index % 8)))) return NULL;
    return (block *)(value - header_bytes());
}
static void *allocate_locked(size_t n) {
    /* Only the same allocation callback's fresh current guard enters here.
     * The fixed-heap walk holds its state lock and invokes no callbacks. */
    size_t size = rounded(n);
    if (!n || !size || (state->closing && !state->cleanup_active) || state->failed) return NULL;
    ALLOCATION_ATTEMPT();
    /* Address-order first fit over free blocks only. A small earlier hole
     * stays eligible without making every request rescan the live prefix. */
    for (block **link = &state->first_free; *link; link = &(*link)->next_free) {
        block *b = *link;
        ALLOCATION_VISIT();
        if (b->requested || b->available < size) continue;
        if (b->available - size >= header_bytes() + alignment) {
            block *after = next_block(b);
            block *tail = (block *)((unsigned char *)payload(b) + size);
            *tail = (block){.available = b->available - size - header_bytes(),
                .previous = b, .next_free = b->next_free};
            if (after) after->previous = tail;
            b->available = size;
            *link = tail;
        } else {
            *link = b->next_free;
        }
        b->next_free = NULL;
        b->requested = n;
        mark_start(b, 1);
        state->live_bytes += n; state->aligned_bytes += b->available; state->blocks++;
        if (state->aligned_bytes > state->peak) state->peak = state->aligned_bytes;
        return payload(b);
    }
    state->failures++;
    return NULL;
}
static void free_locked(block *b) {
    state->live_bytes -= b->requested; state->aligned_bytes -= b->available; state->blocks--;
    mark_start(b, 0);
    OPENSSL_cleanse(payload(b), b->available);
    b->requested = 0;
    block **link = &state->first_free;
    while (*link) {
        FREE_VISIT();
        if ((uintptr_t)*link > (uintptr_t)b) break;
        link = &(*link)->next_free;
    }
    b->next_free = *link;
    *link = b;
    block *next = next_block(b);
    if (next && !next->requested) {
        b->available += header_bytes() + next->available;
        b->next_free = next->next_free;
        block *after = next_block(b);
        if (after) after->previous = b;
    }
    block *previous = b->previous;
    if (previous && !previous->requested) {
        previous->available += header_bytes() + b->available;
        previous->next_free = b->next_free;
        block *after = next_block(previous);
        if (after) after->previous = previous;
    }
}
static void *component_malloc(size_t n, const char *file, int line) {
    (void)file; (void)line;
    if (!lock_current_allocation_state()) return NULL;
    void *result = allocate_locked(n); unlock_state(); return result;
}
static void component_free(void *p, const char *file, int line) {
    (void)file; (void)line;
    if (!p) return;
    if (!lock_state()) return; /* A busy/foreign free never reaches stock free. */
    block *b = find(p);
    if (b) free_locked(b); else {state->failed = 1; state->failures++;}
    unlock_state();
}
static void *component_realloc(void *p, size_t n, const char *file, int line) {
    (void)file; (void)line;
    if (!p) return component_malloc(n, file, line);
    if (!lock_current_allocation_state()) return NULL;
    block *b = find(p);
    if (!b || (state->closing && !state->cleanup_active) || state->failed) {
        if (!b) {state->failed = 1; state->failures++;}
        unlock_state(); return NULL;
    }
    if (!n) {free_locked(b); unlock_state(); return NULL;}
    /* The new allocation must fit while the old allocation remains live. */
    void *next = allocate_locked(n);
    if (next) {memcpy(next, p, n < b->requested ? n : b->requested); free_locked(b);}
    unlock_state(); return next;
}
