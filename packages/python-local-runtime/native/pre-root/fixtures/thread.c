/* Same-provider thread/exit conformance; no Rust, Engine, Run or normal profile. */
#include <pthread.h>
#include <errno.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

/* This fixture calls real pthread operations except ONE explicit, confirmed
 * create refusal. The original product source has no injected function table. */
static int create_calls, join_calls, refuse_next_create;
static int observed_create(pthread_t *t, const pthread_attr_t *a, void *(*f)(void *), void *p) {
    create_calls++;
    if (refuse_next_create) { refuse_next_create = 0; return EAGAIN; }
    return pthread_create(t, a, f, p);
}
static int observed_join(pthread_t t, void **v) {
    join_calls++;
    return pthread_join(t, v);
}
#define pthread_create observed_create
#define pthread_join observed_join
#include "../owned_capacity.c"
#undef pthread_create
#undef pthread_join
#include "../memory_abi.generated.h"

struct fixture {
    actql_owned_capacity *owner;
    void *control;
    atomic_int entered, finish, destructed;
    pthread_key_t key;
    int self_join;
};

static void setup(struct fixture *f) {
    memset(f, 0, sizeof(*f));
    atomic_init(&f->entered, 0); atomic_init(&f->finish, 1); atomic_init(&f->destructed, 0);
    unsigned char recipe[32] = {7};
    long page = sysconf(_SC_PAGESIZE); assert(page > 0);
    assert(actql_native_owned_acquire((size_t)page * 64, 1, recipe, &f->owner) == 0);
    assert(actql_native_owned_enter(f->owner) == 0);
    assert(actql_native_owned_allocate(f->owner, actql_native_owned_thread_control_bytes(),
        actql_native_owned_thread_control_alignment(), &f->control) == 0);
}
static void cleanup(struct fixture *f) {
    assert(actql_native_owned_retire(f->owner, f->control) == 0); f->control = NULL;
    if (actql_native_owned_current() == f->owner) assert(actql_native_owned_leave(f->owner) == 0);
    assert(actql_native_owned_try_close(&f->owner) == 0 && f->owner == NULL);
}
static void child(void *arg) {
    struct fixture *f = arg; void *memory = NULL;
    assert(actql_native_owned_current() == f->owner);
    /* The child cannot discard its runtime-owned lifetime pin. Nested calls
     * still use and leave the SAME existing TLS without consuming that floor. */
    assert(actql_native_owned_leave(f->owner) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_enter(f->owner) == 0);
    assert(actql_native_owned_leave(f->owner) == 0);
    assert(actql_native_owned_current() == f->owner);
    assert(actql_native_owned_allocate(f->owner, 64, 8, &memory) == 0);
    assert(actql_native_owned_retire(f->owner, memory) == 0);
    if (f->self_join) assert(actql_native_owned_thread_join(f->owner, f->control) == ACTQL_OWNED_INVALID);
    atomic_store_explicit(&f->entered, 1, memory_order_release);
    while (!atomic_load_explicit(&f->finish, memory_order_acquire)) sched_yield();
}
static void destructor(void *arg) {
    struct fixture *f = arg; void *memory = NULL;
    assert(actql_native_owned_current() == f->owner);
    assert(actql_native_owned_allocate(f->owner, 64, 8, &memory) == 0);
    assert(actql_native_owned_retire(f->owner, memory) == 0);
    atomic_store_explicit(&f->destructed, 1, memory_order_release);
}
static void with_destructor(void *arg) {
    struct fixture *f = arg;
    assert(pthread_setspecific(f->key, f) == 0);
    child(arg);
}
static void start(struct fixture *f, actql_owned_thread_entry entry) {
    assert(actql_native_owned_thread_start(f->owner, f->control,
        actql_native_owned_thread_control_bytes(), entry, f) == 0);
}

static void original_scope(void) {
    struct fixture f; setup(&f); start(&f, child);
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(atomic_load(&f.entered) == 1 && actql_native_owned_current() == f.owner);
    cleanup(&f);
}
static void thread_destructors(void) {
    struct fixture f; setup(&f); assert(pthread_key_create(&f.key, destructor) == 0);
    start(&f, with_destructor);
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(atomic_load(&f.destructed) == 1); assert(pthread_key_delete(f.key) == 0); cleanup(&f);
}
static void close_and_join(void) {
    struct fixture f; setup(&f); atomic_store(&f.finish, 0); start(&f, child);
    while (!atomic_load_explicit(&f.entered, memory_order_acquire)) sched_yield();
    assert(actql_native_owned_leave(f.owner) == 0);
    assert(actql_native_owned_try_close(&f.owner) == ACTQL_OWNED_BUSY && f.owner != NULL);
    atomic_store_explicit(&f.finish, 1, memory_order_release);
    int before = join_calls;
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(join_calls == before + 1);
    /* Confirmed stop is not storage retirement. */
    assert(actql_native_owned_try_close(&f.owner) == ACTQL_OWNED_BUSY && f.owner != NULL);
    cleanup(&f);
}
static void known_start_refusal(void) {
    struct fixture f; setup(&f); int before = create_calls;
    refuse_next_create = 1;
    assert(actql_native_owned_thread_start(f.owner, f.control,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(actql_native_owned_thread_start(f.owner, f.control,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    assert(create_calls == before + 1 && atomic_load(&f.entered) == 0);
    assert(actql_native_owned_thread_join(f.owner, f.control) == ACTQL_OWNED_INVALID);
    cleanup(&f);
}
static void foreign_storage(void) {
    struct fixture f; setup(&f); actql_owned_capacity *other = NULL; void *foreign = NULL;
    unsigned char recipe[32] = {8}; long page = sysconf(_SC_PAGESIZE);
    assert(actql_native_owned_acquire((size_t)page * 64, 2, recipe, &other) == 0);
    assert(actql_native_owned_allocate(other, actql_native_owned_thread_control_bytes(), 16, &foreign) == 0);
    int before = create_calls;
    assert(actql_native_owned_thread_start(f.owner, foreign,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_thread_start(other, foreign,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    assert(create_calls == before);
    assert(actql_native_owned_retire(other, foreign) == 0 && actql_native_owned_try_close(&other) == 0);
    cleanup(&f);
}
static void copied_storage(void) {
    struct fixture f; setup(&f); start(&f, child);
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    void *copy = NULL; size_t bytes = actql_native_owned_thread_control_bytes();
    assert(actql_native_owned_allocate(f.owner, bytes, 16, &copy) == 0); memcpy(copy, f.control, bytes);
    int before = join_calls;
    assert(actql_native_owned_thread_join(f.owner, copy) == ACTQL_OWNED_INVALID);
    assert(join_calls == before); assert(actql_native_owned_retire(f.owner, copy) == 0); cleanup(&f);
}
static void retired_storage(void) {
    struct fixture f; setup(&f); start(&f, child);
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(actql_native_owned_retire(f.owner, f.control) == 0);
    /* The old page is PROT_NONE: touching it before range admission would crash. */
    int before = join_calls;
    assert(actql_native_owned_thread_join(f.owner, f.control) == ACTQL_OWNED_INVALID);
    assert(join_calls == before); f.control = NULL;
    assert(actql_native_owned_leave(f.owner) == 0 && actql_native_owned_try_close(&f.owner) == 0);
}
static void invalid_input(void) {
    struct fixture f; setup(&f); int before = create_calls;
    assert(actql_native_owned_thread_start(f.owner, f.control, 1, child, &f) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_thread_start(f.owner, (unsigned char *)f.control + 1,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    unsigned char unrelated[256] = {0};
    assert(actql_native_owned_thread_start(f.owner, unrelated,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_leave(f.owner) == 0);
    assert(actql_native_owned_thread_start(f.owner, f.control,
        actql_native_owned_thread_control_bytes(), child, &f) == ACTQL_OWNED_INVALID);
    assert(create_calls == before); cleanup(&f);
}
static void fork_refusal(void) {
    struct fixture f; setup(&f); pid_t pid = fork(); assert(pid >= 0);
    if (pid == 0) {
        int before = create_calls;
        int a = actql_native_owned_thread_start(f.owner, f.control,
            actql_native_owned_thread_control_bytes(), child, &f);
        int b = actql_native_owned_enter(f.owner);
        int c = actql_native_owned_thread_join(f.owner, f.control);
        _exit(a == ACTQL_OWNED_INVALID && b == ACTQL_OWNED_INVALID && c == ACTQL_OWNED_INVALID && create_calls == before ? 0 : 1);
    }
    int status = 0; assert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    cleanup(&f);
}
static void self_join(void) {
    struct fixture f; setup(&f); f.self_join = 1; start(&f, child);
    int before = join_calls;
    assert(actql_native_owned_thread_join(f.owner, f.control) == 0);
    assert(join_calls == before + 1); cleanup(&f);
}

int main(void) {
    const struct {const char *name; void (*run)(void);} cases[] = {
        {"same original pre-callback allocation and nested TLS", original_scope},
        {"same scope through thread-specific destructors", thread_destructors},
        {"parent close pin and join-once versus storage retirement", close_and_join},
        {"known startup failure retains non-reusable original", known_start_refusal},
        {"foreign holding and backing storage refuse", foreign_storage},
        {"copied original controller refuses", copied_storage},
        {"retired controller rejects before inaccessible read", retired_storage},
        {"unfunded malformed and noncurrent startup refuse", invalid_input},
        {"forked context cannot re-adopt original", fork_refusal},
        {"self join refusal preserves parent join", self_join},
    };
    size_t count = sizeof(cases) / sizeof(cases[0]);
    for (size_t i = 0; i < count; i++) {
        fprintf(stderr, "native thread case %zu/%zu: %s\n", i + 1, count, cases[i].name);
        cases[i].run();
    }
    printf("{\"discovered\":%zu,\"executed\":%zu,\"passed\":%zu,\"failed\":0,\"fixture_pages\":64,\"Rust\":0,\"Engine\":0,\"normal_funding\":null}\n", count, count, count);
    return 0;
}
