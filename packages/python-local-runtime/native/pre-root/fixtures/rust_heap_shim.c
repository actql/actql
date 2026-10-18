/* Diagnostic aliases of the same provider for the Rust GlobalAlloc caller. */
#include "../owned_capacity.c"
actql_owned_capacity *actql_owned_current(void);
int actql_owned_rust_allocate(actql_owned_capacity *, size_t, size_t, void **, uint64_t *);
int actql_owned_rust_retire(actql_owned_capacity *, void *, uint64_t);
actql_owned_capacity *actql_owned_current(void) { return actql_native_owned_current(); }
int actql_owned_rust_allocate(actql_owned_capacity *lease, size_t bytes, size_t alignment,
                            void **out, uint64_t *token) {
    return actql_native_owned_rust_allocate(lease, bytes, alignment, out, token);
}
int actql_owned_rust_retire(actql_owned_capacity *lease, void *allocation, uint64_t token) {
    return actql_native_owned_rust_retire(lease, allocation, token);
}
