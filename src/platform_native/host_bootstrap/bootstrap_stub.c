/* The installed supplier's declared control envelope owns these fixed external
 * records. The backing and every child extent use the original C adapter.
 * There is no GC cleanup ACK: the MoonBit Host retains all records until explicit
 * child-first cleanup. Unreachable live records cannot release a reservation. */
#include "moonbit.h"
#include <stdint.h>
#include <string.h>
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.c"
#include "../../../packages/python-local-runtime/native/pre-root/owned_image.c"

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

/* One same-provider physical loan, retained by the original Native/Core carrier.
 * This fixed record belongs to the existing control envelope, not child bytes. */
typedef struct {
    actql_bootstrap_backing *owner;
    actql_bootstrap_extent *extent;
    actql_owned_extent_loan loan;
    int status;
} actql_bootstrap_region;

MOONBIT_FFI_EXPORT void *actql_bootstrap_lend_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    int64_t offset, int64_t length, int32_t writable) {
    actql_bootstrap_region *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->owner = owner;
    record->extent = extent;
    record->status = ACTQL_OWNED_INVALID;
    if (extent->owner == owner && extent->address != NULL &&
        offset >= 0 && length > 0 && (uint64_t)offset <= SIZE_MAX &&
        (uint64_t)length <= SIZE_MAX && (writable == 0 || writable == 1)) {
        record->status = actql_native_owned_lend_extent_range(
            owner->lease, extent->address, (size_t)offset, (size_t)length,
            writable != 0, &record->loan);
    }
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_region_status(actql_bootstrap_region *record) {
    return record->status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_return_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    actql_bootstrap_region *record) {
    if (record->owner != owner || record->extent != extent || extent->owner != owner)
        return ACTQL_OWNED_INVALID;
    /* A failed pre-lend has published no view/borrower. This is not evidence
     * of stopping a successfully entered child; the Native caller supplies it. */
    if (record->loan.original == NULL) return ACTQL_OWNED_OK;
    return actql_native_owned_return_extent(&record->loan);
}

/* Bounded immutable DATA capture, never an owning pointer or child grant. */
typedef struct {
    actql_owned_extent_reference extent;
    int64_t allocation_offset;
    int status;
} actql_bootstrap_projection;

MOONBIT_FFI_EXPORT void *actql_bootstrap_project_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    actql_bootstrap_region *loan) {
    actql_bootstrap_projection *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->status = ACTQL_OWNED_INVALID;
    if (loan->owner == owner && loan->extent == extent && extent->owner == owner &&
        owner->lease != NULL && extent->address != NULL) {
        record->status = actql_native_owned_project_extent(&loan->loan, &record->extent);
        if (record->status == ACTQL_OWNED_OK) {
            uintptr_t start = (uintptr_t)extent->address;
            uintptr_t base = (uintptr_t)owner->lease;
            if (record->extent.device > INT64_MAX || record->extent.inode > INT64_MAX ||
                record->extent.generation > INT64_MAX || record->extent.capacity > INT64_MAX ||
                record->extent.offset > INT64_MAX || record->extent.length > INT64_MAX ||
                start < base || start - base > INT64_MAX)
                record->status = ACTQL_OWNED_INVALID;
            else record->allocation_offset = (int64_t)(start - base);
        }
    }
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_projection_status(actql_bootstrap_projection *record) {
    return record->status;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_projection_scalar(
    actql_bootstrap_projection *record, int32_t ordinal) {
    if (record->status != ACTQL_OWNED_OK) return -1;
    switch (ordinal) {
    case 0: return (int64_t)record->extent.device;
    case 1: return (int64_t)record->extent.inode;
    case 2: return (int64_t)record->extent.generation;
    case 3: return (int64_t)record->extent.capacity;
    case 4: return (int64_t)record->extent.offset;
    case 5: return (int64_t)record->extent.length;
    case 6: return record->extent.writable ? 1 : 0;
    case 7: return record->allocation_offset;
    default: return -1;
    }
}

MOONBIT_FFI_EXPORT moonbit_bytes_t actql_bootstrap_projection_recipe(
    actql_bootstrap_projection *record) {
    if (record->status != ACTQL_OWNED_OK) return moonbit_make_bytes(0, 0);
    moonbit_bytes_t bytes = moonbit_make_bytes(32, 0);
    memcpy(bytes, record->extent.recipe, 32);
    return bytes;
}

typedef struct {
    actql_bootstrap_region *loan;
    actql_owned_extent_view view;
    int status;
} actql_bootstrap_view;

MOONBIT_FFI_EXPORT void *actql_bootstrap_map_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    actql_bootstrap_region *loan, int32_t fd, int64_t payload_offset, int64_t payload_length) {
    actql_bootstrap_view *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->loan = loan;
    record->status = ACTQL_OWNED_INVALID;
    if (loan->owner == owner && loan->extent == extent && extent->owner == owner) {
        actql_owned_extent_reference reference;
        record->status = actql_native_owned_project_extent(&loan->loan, &reference);
        if (record->status == ACTQL_OWNED_OK) {
            if (payload_offset < 0 || payload_length <= 0 ||
                (uint64_t)payload_offset > SIZE_MAX || (uint64_t)payload_length > SIZE_MAX)
                record->status = ACTQL_OWNED_INVALID;
            else record->status = actql_native_owned_map_extent_payload(
                fd, &reference, (size_t)payload_offset, (size_t)payload_length, &record->view);
        }
    }
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_view_status(actql_bootstrap_view *record) {
    return record->status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_close_region_view(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    actql_bootstrap_region *loan, actql_bootstrap_view *record) {
    if (loan->owner != owner || loan->extent != extent || extent->owner != owner ||
        record->loan != loan) return ACTQL_OWNED_INVALID;
    /* A pre-map refusal published no mapping. Post-map failure still has its
     * exact original view and is retired through the existing retry port. */
    if (record->view.original == NULL && record->view.mapping == NULL)
        return ACTQL_OWNED_OK;
    return actql_native_owned_close_extent_view(&record->view);
}

/* The same external record retains the original interior slot across failure.
 * Its lifetime belongs to the initial declared control envelope, not new bytes. */
typedef struct {
    actql_bootstrap_view *view;
    actql_owned_capacity *lease;
    int status;
} actql_bootstrap_domain;

MOONBIT_FFI_EXPORT void *actql_bootstrap_acquire_domain(actql_bootstrap_view *view) {
    actql_bootstrap_domain *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    record->view = view;
    record->lease = NULL;
    record->status = view->status == ACTQL_OWNED_OK
        ? actql_native_owned_acquire_extent_domain(&view->view, &record->lease)
        : view->status;
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_domain_status(actql_bootstrap_domain *record) {
    return record->status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_transfer_domain(actql_bootstrap_domain *record) {
    if (record->lease == NULL) return ACTQL_OWNED_INVALID;
    return actql_native_owned_transfer(record->lease, record->lease->generation, record->lease->recipe);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_enter_domain(actql_bootstrap_domain *record) {
    return actql_native_owned_enter(record->lease);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_leave_domain(actql_bootstrap_domain *record) {
    return actql_native_owned_leave(record->lease);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_close_domain(
    actql_bootstrap_view *view, actql_bootstrap_domain *record) {
    if (record->view != view) return ACTQL_OWNED_INVALID;
    /* Pre-acquire refusal published no interior lease. Its same original
     * outer view still requires separate Owner-confirmed cleanup. */
    if (record->lease == NULL && record->status != ACTQL_OWNED_OK)
        return ACTQL_OWNED_OK;
    return actql_native_owned_close_extent_domain(&view->view, &record->lease);
}
