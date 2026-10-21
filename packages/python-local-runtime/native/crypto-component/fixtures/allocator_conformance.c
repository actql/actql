#define _DARWIN_C_SOURCE
#include "owned_capacity.h"
#include "scoped_read.h"
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

/* Compile the provider separately. Including this private allocator permits
 * exact membership/metadata assertions without exporting raw allocation ports. */
actql_read_context *actql_bootstrap_current_read_context(void) {
    return actql_read_context_current();
}
#include "../component.c"

static void audit(void) {
    size_t blocks = 0, requested = 0, aligned = 0;
    block *previous = NULL;
    for (block *b = state->first; b; b = next_block(b)) {
        assert(b->previous == previous);
        assert(b->available >= alignment && b->available % alignment == 0);
        assert(find(payload(b)) == (b->requested ? b : NULL));
        if (b->requested) {
            blocks++;
            requested += b->requested;
            aligned += b->available;
        } else {
            assert(!next_block(b) || next_block(b)->requested);
        }
        previous = b;
    }
    assert(blocks == state->blocks && requested == state->live_bytes && aligned == state->aligned_bytes);
    size_t starts = 0;
    for (size_t i = 0; i < (state->bytes / alignment + 7) / 8; i++)
        for (unsigned bit = 0; bit < 8; bit++) starts += !!(state->live_starts[i] & (1u << bit));
    assert(starts == blocks);
    uint64_t inventory[12] = {0};
    assert(actql_crypto_component_inventory(inventory) == 0);
    assert(inventory[2] + inventory[5] + inventory[6] == inventory[0]);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    unsigned char recipe[32] = {29};
    actql_owned_capacity *owner = NULL;
    actql_read_context *context = NULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    assert(actql_native_owned_acquire(384 * page, 1, recipe, &owner) == 0);
    assert(actql_native_owned_transfer(owner, 1, recipe) == 0);
    assert(actql_native_owned_enter(owner) == 0);
    assert(actql_read_context_create(owner, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    assert(actql_read_context_enter(context) == 0);
    int acquired = 0;
    int partial = !strcmp(argv[1], "partial");
    assert(partial || !strcmp(argv[1], "split-merge-membership"));
    int bound = actql_crypto_component_bind_current_with_custody(partial ? 4096 : 4 * 1024 * 1024, &acquired);
    assert(acquired == 1);
    if (partial) {
        assert(bound == ACTQL_CRYPTO_COMPONENT_FAILED);
    } else {
        assert(bound == 0);
        assert(actql_crypto_component_borrow_library() == 0);
        assert(actql_crypto_component_enter_current() == 0);
        audit();
        size_t baseline_blocks = state->blocks, baseline_bytes = state->live_bytes;
        unsigned char *slots[64] = {0};
        for (size_t i = 0; i < 64; i++) {
            size_t n = 128 + i * 17;
            slots[i] = component_malloc(n, __FILE__, __LINE__);
            assert(slots[i] && find(slots[i]));
            memset(slots[i], (int)(i + 1), n);
            assert(!find(slots[i] + 1) && !find(slots[i] + alignment));
        }
        audit();
        void *guard = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        assert(guard != MAP_FAILED);
        assert(!find(guard) && !find((void *)UINTPTR_MAX) && !find(state->live_starts));
        assert(munmap(guard, page) == 0);
        for (size_t i = 0; i < 64; i += 2) {
            block *b = find(slots[i]);
            size_t aligned = b->available;
            component_free(slots[i], __FILE__, __LINE__);
            assert(!find(slots[i]));
            for (size_t j = 0; j < aligned; j++) assert(slots[i][j] == 0);
        }
        audit();
        for (size_t i = 1; i < 64; i += 2) {
            size_t old = 128 + i * 17;
            unsigned char *next = component_realloc(slots[i], old * 2, __FILE__, __LINE__);
            assert(next);
            for (size_t j = 0; j < old; j++) assert(next[j] == (unsigned char)(i + 1));
            assert(!find(slots[i]));
            slots[i] = next;
        }
        audit();
        assert(component_realloc(slots[1], SIZE_MAX, __FILE__, __LINE__) == NULL);
        assert(find(slots[1]) && slots[1][0] == 2);
        /* Reverse order exercises both neighbor merges. A cleared start stays
         * retired even when its old header has become interior free storage. */
        for (size_t i = 64; i > 0;) {
            i--;
            if (i % 2) component_free(slots[i], __FILE__, __LINE__);
        }
        audit();
        assert(state->blocks == baseline_blocks && state->live_bytes == baseline_bytes);
        unsigned char *reused = component_malloc(8192, __FILE__, __LINE__);
        assert(reused && find(reused));
        component_free(reused, __FILE__, __LINE__);
        audit();
        assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_BUSY);
        assert(actql_crypto_component_leave_current() == 0);
        assert(actql_crypto_component_release_library() == 0);
    }
    assert(actql_crypto_component_close() == 0);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(owner) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == 0 && context == NULL);
    assert(actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    printf("{\"case\":\"%s\",\"passed\":true,\"original_cleanup\":true}\n", argv[1]);
    return 0;
}
