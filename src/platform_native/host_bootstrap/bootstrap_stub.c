/* The installed supplier's declared control envelope owns these fixed external
 * records. The backing and every child extent use the original C adapter.
 * There is no GC cleanup ACK: the MoonBit Host retains all records until explicit
 * child-first cleanup. Unreachable live records cannot release a reservation. */
#include "moonbit.h"
#include <stdint.h>
#include <string.h>
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.c"

typedef struct {
    actql_owned_capacity *lease;
    int status;
} actql_bootstrap_backing;

typedef struct {
    actql_bootstrap_backing *owner;
    void *address;
    int status;
} actql_bootstrap_extent;

static void keep_physical_custody(void *record) {
    /* A finalizer is not evidence of native retirement. */
    (void)record;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_page_bytes(void) {
    return (int64_t)sysconf(_SC_PAGESIZE);
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_acquire(int64_t bytes,
                                               int64_t generation,
                                               const unsigned char *recipe) {
    actql_bootstrap_backing *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    record->lease = NULL;
    record->status = ACTQL_OWNED_INVALID;
    if (bytes > 0 && (uint64_t)bytes <= SIZE_MAX && generation > 0) {
        record->status = actql_native_owned_acquire((size_t)bytes,
                           (uint64_t)generation, recipe, &record->lease);
    }
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_status(actql_bootstrap_backing *record) {
    return record->status;
}

/* Same external carrier, reservation order and provider as anonymous acquire.
 * The trusted original caller retains the borrowed FD; no implicit dup/close. */
MOONBIT_FFI_EXPORT void *actql_bootstrap_acquire_fd(int32_t fd, int64_t bytes,
                                                  int64_t generation,
                                                  const unsigned char *recipe) {
    actql_bootstrap_backing *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    record->lease = NULL;
    record->status = ACTQL_OWNED_INVALID;
    if (fd >= 0 && bytes > 0 && (uint64_t)bytes <= SIZE_MAX && generation > 0) {
        record->status = actql_native_owned_acquire_fd(fd, (size_t)bytes,
                           (uint64_t)generation, recipe, &record->lease);
    }
    return record;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_control_bytes(actql_bootstrap_backing *record) {
    if (record->lease == NULL) return -1;
    return (int64_t)(record->lease->control_pages * record->lease->page_size);
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_rounded_bytes(actql_bootstrap_backing *record,
                                                       int64_t bytes) {
    if (record->lease == NULL || bytes <= 0 || (uint64_t)bytes > SIZE_MAX) return -1;
    size_t pages;
    if (!round_pages((size_t)bytes, record->lease->page_size, &pages) ||
        pages > record->lease->page_count) return -1;
    return (int64_t)(pages * record->lease->page_size);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_claim(actql_bootstrap_backing *record,
                                               int64_t generation,
                                               const unsigned char *recipe) {
    return actql_native_owned_transfer(record->lease, (uint64_t)generation, recipe);
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_allocate(actql_bootstrap_backing *record,
                                                int64_t bytes) {
    actql_bootstrap_extent *extent = moonbit_make_external_object(
        keep_physical_custody, sizeof(*extent));
    extent->owner = record;
    extent->address = NULL;
    extent->status = ACTQL_OWNED_INVALID;
    if (bytes > 0 && (uint64_t)bytes <= SIZE_MAX) {
        extent->status = actql_native_owned_allocate(record->lease,
                                    (size_t)bytes, 1, &extent->address);
    }
    return extent;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_extent_status(actql_bootstrap_extent *extent) {
    return extent->status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_retire(actql_bootstrap_backing *record,
                                                actql_bootstrap_extent *extent) {
    if (extent->owner != record) return ACTQL_OWNED_INVALID;
    /* A failed acquisition with no published pointer is confirmed unstarted. */
    if (extent->address == NULL) return ACTQL_OWNED_OK;
    int status = actql_native_owned_retire(record->lease, extent->address);
    if (status == ACTQL_OWNED_OK) extent->address = NULL;
    return status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_close(actql_bootstrap_backing *record) {
    return actql_native_owned_try_close(&record->lease);
}

/* Nominal Host/loan checks precede these calls in the existing Native Owner.
 * The same backing owns the only allocator/TLS; no pointer is exported. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_enter_scope(actql_bootstrap_backing *record) {
    return actql_native_owned_enter(record->lease);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_leave_scope(actql_bootstrap_backing *record) {
    return actql_native_owned_leave(record->lease);
}
