/* Diagnostic-only same provider, not an installed Native control library. */
#include <stdio.h>
#include "../owned_capacity.c"

void actql_test_original_extent_observation(actql_owned_capacity *owner, int phase) {
    lock_capacity(owner);
    fprintf(stderr, "original physical observation phase=%d scopes=%zu\n", phase, owner->active_scopes);
    for (size_t i = owner->control_pages; i < owner->page_count; i++) {
        struct extent *record = &owner->extents[i];
        if (record->pages == 0 || record->pages == SIZE_MAX) continue;
        fprintf(stderr, "extent page=%zu pages=%zu retired=%d", i, record->pages, record->retired);
        if (!record->retired) {
            /* Read only an admitted live extent, never a retired PROT_NONE page.
             * Original Rust allocation header shape is independently checked;
             * this is diagnostic DATA, no new allocator or cleanup authority. */
            uintptr_t words[4];
            void *start = (unsigned char *)owner + i * owner->page_size;
            memcpy(words, start, sizeof(words));
            if (words[0] == (uintptr_t)owner && words[1] == (uintptr_t)start)
                fprintf(stderr, " original-Rust-bytes=%zu alignment=%zu", (size_t)words[2], (size_t)words[3]);
        }
        fputc('\n', stderr);
    }
    unlock_capacity(owner);
}
