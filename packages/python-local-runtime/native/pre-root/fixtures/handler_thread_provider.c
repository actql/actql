/* Diagnostic-only same provider, not an installed Native control library. */
#include <stdio.h>
#include <unwind.h>
#include <dlfcn.h>
#define actql_native_owned_allocate actql_test_original_allocate_body
#include "../owned_capacity.c"
#undef actql_native_owned_allocate

/* Bounded test-only DATA; never consulted for capacity, cleanup or admission. */
struct allocation_trace { void *allocation; uintptr_t frames[20]; size_t count; };
static struct allocation_trace traces[64];
static size_t trace_count;
static _Unwind_Reason_Code record_frame(struct _Unwind_Context *context, void *argument) {
    struct allocation_trace *trace = argument;
    if (trace->count == 20) return _URC_END_OF_STACK;
    trace->frames[trace->count++] = (uintptr_t)_Unwind_GetIP(context);
    return _URC_NO_REASON;
}
int actql_native_owned_allocate(actql_owned_capacity *owner, size_t bytes,
                                size_t alignment, void **out) {
    int code = actql_test_original_allocate_body(owner, bytes, alignment, out);
    /* Original Rust header32 + observed payload64. Capture only this contact;
     * no allocation quantity/meaning is changed and no alternative provider runs. */
    if (code == 0 && bytes == 96 && trace_count < 64) {
        struct allocation_trace *trace = &traces[trace_count++];
        trace->allocation = *out;
        _Unwind_Backtrace(record_frame, trace);
    }
    return code;
}

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
            for (size_t t = trace_count; t > 0; t--) {
                const struct allocation_trace *trace = &traces[t - 1];
                if (trace->allocation != start) continue;
                for (size_t f = 0; f < trace->count; f++) {
                    Dl_info info;
                    if (dladdr((void *)trace->frames[f], &info) != 0)
                        fprintf(stderr, "\n  frame%zu image=%s offset=%zx symbol=%s", f,
                            info.dli_fname, (size_t)(trace->frames[f] - (uintptr_t)info.dli_fbase),
                            info.dli_sname == NULL ? "<private>" : info.dli_sname);
                }
                break;
            }
        }
        fputc('\n', stderr);
    }
    unlock_capacity(owner);
}
