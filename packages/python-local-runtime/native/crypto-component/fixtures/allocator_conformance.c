#define _DARWIN_C_SOURCE
#include "owned_capacity.h"
#include "scoped_read.h"
#include <assert.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

static int observe_callbacks;
static size_t callback_process_queries, callback_provider_queries;
/* Observe real process queries in this component and its separately compiled
 * original provider. Never replace the kernel result or a current Read. */
pid_t actql_crypto_fixture_getpid(void) {
    if (observe_callbacks) callback_process_queries++;
    return getpid();
}

/* Compile the provider separately. Including this private allocator permits
 * exact membership/metadata assertions without exporting raw allocation ports. */
actql_read_context *actql_bootstrap_current_read_context(void) {
    if (observe_callbacks) callback_provider_queries++;
    return actql_read_context_current();
}
#define ACTQL_CRYPTO_COMPONENT_TEST_SEARCH
#define getpid actql_crypto_fixture_getpid
#include "../component.c"
#undef getpid

static void observe_callback(void) {
    callback_process_queries = callback_provider_queries = 0;
    observe_callbacks = 1;
}
static void observed_callback(size_t provider_queries, size_t process_queries) {
    observe_callbacks = 0;
    assert(callback_provider_queries == provider_queries);
    assert(callback_process_queries == process_queries);
}

typedef struct {
    CRYPTO_malloc_fn allocate;
    CRYPTO_realloc_fn resize;
    CRYPTO_free_fn release;
    void *pointer;
} callback_probe;
static void *foreign_callback_thread(void *raw) {
    callback_probe *probe = raw;
    assert(probe->allocate(32, __FILE__, __LINE__) == NULL);
    assert(probe->resize(probe->pointer, 96, __FILE__, __LINE__) == NULL);
    probe->release(probe->pointer, __FILE__, __LINE__);
    return NULL;
}

static void callback_current(actql_owned_capacity *owner, actql_read_context *context) {
    CRYPTO_malloc_fn allocate;
    CRYPTO_realloc_fn resize;
    CRYPTO_free_fn release;
    CRYPTO_get_mem_functions(&allocate, &resize, &release);
    assert(allocate == component_malloc && resize == component_realloc && release == component_free);
    size_t baseline_blocks = state->blocks, baseline_bytes = state->live_bytes;
    observe_callback();
    unsigned char *pointer = allocate(48, __FILE__, __LINE__);
    assert(pointer); observed_callback(1, 1); memset(pointer, 73, 48);
    observe_callback();
    unsigned char *resized = resize(pointer, 96, __FILE__, __LINE__);
    assert(resized); observed_callback(1, 1);
    for (size_t i = 0; i < 48; i++) assert(resized[i] == 73);
    assert(!find(pointer)); pointer = resized;
    observe_callback();
    assert(resize(pointer, SIZE_MAX, __FILE__, __LINE__) == NULL);
    observed_callback(1, 1);
    assert(find(pointer) && pointer[0] == 73 && !state->failed);

    /* A busy/reentrant callback does not construct or consume an old block. */
    assert(!atomic_flag_test_and_set_explicit(&state->lock, memory_order_acquire));
    observe_callback();
    assert(allocate(32, __FILE__, __LINE__) == NULL);
    assert(resize(pointer, 128, __FILE__, __LINE__) == NULL);
    observed_callback(2, 2);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
        alarm(2);
        callback_probe probe = {allocate, resize, release, pointer};
        foreign_callback_thread(&probe);
        assert(pointer[0] == 73);
        _exit(0);
    }
    int status = 0; assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    atomic_flag_clear_explicit(&state->lock, memory_order_release);
    assert(find(pointer) && pointer[0] == 73);

    callback_probe probe = {allocate, resize, release, pointer};
    pthread_t thread;
    observe_callback();
    assert(pthread_create(&thread, NULL, foreign_callback_thread, &probe) == 0);
    assert(pthread_join(thread, NULL) == 0);
    observed_callback(0, 0);
    assert(find(pointer) && pointer[0] == 73 && !state->failed);

    /* Every subsequent callback must observe the actual current scope anew. */
    assert(actql_read_context_leave(context) == 0);
    observe_callback();
    assert(allocate(32, __FILE__, __LINE__) == NULL);
    assert(resize(pointer, 128, __FILE__, __LINE__) == NULL);
    observed_callback(2, 2);
    actql_read_context *foreign = NULL;
    assert(actql_read_context_create(owner, &foreign) == 0);
    assert(actql_read_context_retain(foreign) == 0);
    assert(actql_read_context_enter(foreign) == 0);
    observe_callback();
    assert(allocate(32, __FILE__, __LINE__) == NULL);
    assert(resize(pointer, 128, __FILE__, __LINE__) == NULL);
    observed_callback(2, 2);
    assert(actql_read_context_leave(foreign) == 0);
    assert(actql_read_context_release_after_owner_ack(foreign) == 0);
    assert(actql_read_context_try_close(&foreign) == 0 && !foreign);
    assert(find(pointer) && pointer[0] == 73 && !state->failed);
    observe_callback();
    release(pointer, __FILE__, __LINE__); /* Late cleanup needs no active Read. */
    observed_callback(0, 1);
    assert(!find(pointer));
    assert(actql_read_context_enter(context) == 0);
    observe_callback();
    pointer = resize(NULL, 32, __FILE__, __LINE__);
    assert(pointer); observed_callback(1, 1);
    observe_callback();
    assert(resize(pointer, 0, __FILE__, __LINE__) == NULL);
    observed_callback(1, 1); assert(!find(pointer));
    pointer = allocate(32, __FILE__, __LINE__); assert(pointer);
    observe_callback();
    release(pointer, __FILE__, __LINE__);
    observed_callback(0, 1);
    assert(state->blocks == baseline_blocks && state->live_bytes == baseline_bytes && !state->failed);
    puts("{\"measurement\":\"actual-callback-current\",\"mallocProviderQueries\":1,"
         "\"mallocProcessQueries\":1,\"reallocProviderQueries\":1,\"reallocProcessQueries\":1,"
         "\"freeProviderQueries\":0,\"freeProcessQueries\":1,\"scopeAndForkRefusals\":true}");
}

static void callback_invalid(const char *mode, size_t page) {
    CRYPTO_malloc_fn allocate;
    CRYPTO_realloc_fn resize;
    CRYPTO_free_fn release;
    CRYPTO_get_mem_functions(&allocate, &resize, &release);
    unsigned char *pointer = allocate(48, __FILE__, __LINE__); assert(pointer);
    memset(pointer, 59, 48);
    void *guard = NULL, *invalid = pointer + 1;
    if (!strcmp(mode, "callback-invalid-protected")) {
        guard = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        assert(guard != MAP_FAILED); invalid = guard;
    }
    size_t failures = state->failures, blocks = state->blocks;
    observe_callback();
    assert(resize(invalid, 96, __FILE__, __LINE__) == NULL);
    observed_callback(1, 1);
    assert(state->failed && state->failures == failures + 1 && state->blocks == blocks);
    assert(find(pointer) && pointer[0] == 59);
    assert(allocate(32, __FILE__, __LINE__) == NULL);
    if (guard) assert(munmap(guard, page) == 0);
    (void)release;
}

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

/* Independent physical-chain census: the allocation search must not revisit
 * live headers merely because an earlier free hole is too small. */
static size_t free_block_count(void) {
    size_t count = 0;
    for (block *b = state->first; b; b = next_block(b)) count += !b->requested;
    return count;
}
static int bounded_search(void) {
    enum { count = 512, holes = 32, probes = 64, iterations = 128 };
    unsigned char *slots[count] = {0}, *holes_original[holes] = {0};
    size_t original_blocks = state->blocks, original_bytes = state->live_bytes;
    size_t before = allocation_visits, free_bound = free_block_count();
    for (size_t i = 0; i < count; i++) {
        slots[i] = component_malloc(64, __FILE__, __LINE__);
        assert(slots[i]); memset(slots[i], (int)(i % 251 + 1), 64);
    }
    size_t prefix_visits = allocation_visits - before;
    size_t prefix_limit = count * free_bound;
    assert(prefix_visits >= count && free_bound > 0);
    audit();
    /* Earlier undersized holes remain eligible for a later small request.
     * Large requests must not walk the intervening long-lived blocks. */
    for (size_t i = 0; i < holes; i++) {
        size_t index = 128 + 2 * i;
        holes_original[i] = slots[index];
        component_free(slots[index], __FILE__, __LINE__); slots[index] = NULL;
    }
    before = allocation_visits; free_bound = free_block_count();
    size_t free_before = free_visits;
    for (size_t i = 0; i < probes; i++) {
        void *p = component_malloc(4096, __FILE__, __LINE__);
        assert(p); memset(p, 83, 4096); component_free(p, __FILE__, __LINE__);
    }
    size_t mixed_visits = allocation_visits - before;
    size_t mixed_limit = probes * free_bound;
    size_t mixed_free_visits = free_visits - free_before;
    assert(mixed_visits >= probes && free_bound >= holes);
    for (size_t i = 0; i < holes; i++) {
        size_t index = 128 + 2 * i;
        slots[index] = component_malloc(64, __FILE__, __LINE__);
        assert(slots[index] == holes_original[i]); memset(slots[index], 91, 64);
    }
    audit();
    /* Both-neighbor merge must retire the two interior payload starts. */
    size_t adjacent = 256;
    while (adjacent + 2 < count &&
           (next_block(find(slots[adjacent])) != find(slots[adjacent + 1]) ||
            next_block(find(slots[adjacent + 1])) != find(slots[adjacent + 2]))) adjacent++;
    assert(adjacent + 2 < count);
    unsigned char *merged_start = slots[adjacent];
    component_free(slots[adjacent], __FILE__, __LINE__); slots[adjacent] = NULL;
    component_free(slots[adjacent + 2], __FILE__, __LINE__); slots[adjacent + 2] = NULL;
    component_free(slots[adjacent + 1], __FILE__, __LINE__); slots[adjacent + 1] = NULL;
    assert(!find(merged_start + 64 + header_bytes()));
    unsigned char *merged = component_malloc(192, __FILE__, __LINE__);
    assert(merged == merged_start); slots[adjacent] = merged;
    memset(merged, 97, 192);
    audit();
    unsigned char *filled[128] = {0}; size_t filled_count = 0;
    while (filled_count < 128) {
        void *p = component_malloc(65536, __FILE__, __LINE__);
        if (!p) break;
        filled[filled_count++] = p;
    }
    assert(filled_count > 0 && filled_count < 128);
    unsigned char old = slots[1][0];
    assert(component_realloc(slots[1], state->bytes, __FILE__, __LINE__) == NULL);
    assert(find(slots[1]) && slots[1][0] == old);
    unsigned char *earlier = slots[400];
    component_free(earlier, __FILE__, __LINE__); slots[400] = NULL;
    slots[400] = component_malloc(64, __FILE__, __LINE__);
    assert(slots[400] == earlier);
    for (size_t i = filled_count; i > 0;) component_free(filled[--i], __FILE__, __LINE__);
    audit();
    /* Real OpenSSL digest/HMAC work while mixed holes and long-lived objects
     * coexist. Counters measure allocator traversal, not elapsed speedup. */
    unsigned char key[32] = {17}, input[2048] = {29}, output[EVP_MAX_MD_SIZE];
    before = allocation_visits; size_t attempts_before = allocation_attempts;
    free_before = free_visits;
    for (size_t i = 0; i < iterations; i++) {
        EVP_MD_CTX *context = EVP_MD_CTX_new(); unsigned length = 0;
        assert(context && EVP_DigestInit_ex(context, EVP_sha256(), NULL) == 1);
        assert(EVP_DigestUpdate(context, input, sizeof input) == 1);
        assert(EVP_DigestFinal_ex(context, output, &length) == 1 && length == 32);
        EVP_MD_CTX_free(context);
        assert(HMAC(EVP_sha256(), key, sizeof key, input, sizeof input, output, &length) && length == 32);
    }
    size_t crypto_visits = allocation_visits - before;
    size_t crypto_attempts = allocation_attempts - attempts_before;
    size_t crypto_free_visits = free_visits - free_before;
    assert(crypto_attempts > iterations && crypto_visits >= crypto_attempts);
    for (size_t i = count; i > 0;) { i--; if (slots[i]) component_free(slots[i], __FILE__, __LINE__); }
    audit();
    /* Digest algorithm fetches may remain in OpenSSL's original cache; its
     * original close below, not a fixture reset, owns their eventual release. */
    assert(state->blocks >= original_blocks && state->live_bytes >= original_bytes);
    printf("{\"measurement\":\"actual-search\",\"prefix_visits\":%zu,\"prefix_limit\":%zu,"
           "\"mixed_visits\":%zu,\"mixed_limit\":%zu,\"mixed_free_visits\":%zu,"
           "\"crypto_visits\":%zu,\"crypto_allocations\":%zu,\"crypto_free_visits\":%zu,"
           "\"sha256_operations\":%u,\"hmac_operations\":%u}\n",
           prefix_visits, prefix_limit, mixed_visits, mixed_limit, mixed_free_visits,
           crypto_visits, crypto_attempts, crypto_free_visits, iterations, iterations);
    return prefix_visits <= prefix_limit && mixed_visits <= mixed_limit;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    unsigned char recipe[32] = {29};
    actql_owned_capacity *owner = NULL;
    actql_read_context *context = NULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    /* Preserve the original 6MiB owner on both 16KiB Darwin and 4KiB Linux
     * pages. The selected Crypto extent below remains exactly 4MiB. */
    assert((6 * 1024 * 1024) % page == 0);
    assert(actql_native_owned_acquire(6 * 1024 * 1024, 1, recipe, &owner) == 0);
    assert(actql_native_owned_transfer(owner, 1, recipe) == 0);
    assert(actql_native_owned_enter(owner) == 0);
    assert(actql_read_context_create(owner, &context) == 0);
    assert(actql_read_context_retain(context) == 0);
    assert(actql_read_context_enter(context) == 0);
    int acquired = 0;
    int partial = !strcmp(argv[1], "partial");
    int search = !strcmp(argv[1], "bounded-search");
    int callbacks = !strcmp(argv[1], "callback-current");
    int invalid = !strcmp(argv[1], "callback-invalid-interior") ||
        !strcmp(argv[1], "callback-invalid-protected");
    int search_passed = 1;
    assert(partial || search || callbacks || invalid || !strcmp(argv[1], "split-merge-membership"));
    int bound = actql_crypto_component_bind_current_with_custody(partial ? 4096 : 4 * 1024 * 1024, &acquired);
    assert(acquired == 1);
    if (partial) {
        assert(bound == ACTQL_CRYPTO_COMPONENT_FAILED);
        assert(actql_crypto_component_enter_current() != 0);
        assert(actql_crypto_component_borrow_library() != 0);
        assert(actql_crypto_component_symbol("EVP_sha256") == NULL);
    } else {
        assert(bound == 0);
        assert(actql_crypto_component_borrow_library() == 0);
        assert(actql_crypto_component_enter_current() == 0);
        assert(actql_crypto_component_symbol("EVP_sha256") != NULL);
        audit();
        if (callbacks) {callback_current(owner, context); audit();}
        else if (invalid) callback_invalid(argv[1], page);
        else if (search) search_passed = bounded_search();
        else {
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
        }
        assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_BUSY);
        assert(actql_crypto_component_leave_current() == 0);
        assert(actql_crypto_component_release_library() == 0);
    }
    if (invalid) {
        /* A genuine invalid-current pointer makes the allocator sticky-failed.
         * Do not clear it or invent a cleanup ACK to make a negative pass. The
         * exact retained extent/context survive until this actual process exits. */
        assert(actql_crypto_component_close() == ACTQL_CRYPTO_COMPONENT_BUSY);
        assert(state && original_extent && context_retained && !heap_ack && !context_ack);
        assert(actql_read_context_leave(context) == 0);
        assert(actql_native_owned_leave(owner) == 0);
        assert(actql_read_context_release_after_owner_ack(context) == 0);
        assert(actql_read_context_try_close(&context) != 0 && context);
        assert(actql_native_owned_try_close(&owner) != 0 && owner);
        printf("{\"case\":\"%s\",\"passed\":true,\"original_cleanup\":false,"
               "\"failure_custody\":true,\"physical_stop\":\"process-exit-required\"}\n", argv[1]);
        return 0;
    }
    assert(actql_crypto_component_close() == 0);
    assert(actql_read_context_leave(context) == 0);
    assert(actql_native_owned_leave(owner) == 0);
    assert(actql_read_context_release_after_owner_ack(context) == 0);
    assert(actql_read_context_try_close(&context) == 0 && context == NULL);
    assert(actql_native_owned_try_close(&owner) == 0 && owner == NULL);
    printf("{\"case\":\"%s\",\"passed\":%s,\"original_cleanup\":true}\n", argv[1], search_passed ? "true" : "false");
    return search_passed ? 0 : 1;
}
