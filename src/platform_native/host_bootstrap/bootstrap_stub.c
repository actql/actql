/* The installed supplier's declared control envelope owns these fixed external
 * records. The backing and every child extent use the original C adapter.
 * There is no GC cleanup ACK: the MoonBit Host retains all records until explicit
 * child-first cleanup. Unreachable live records cannot release a reservation. */
/* This package's default POSIX process implementation selects its actual
 * compiler target. Scoped/imported providers keep their separate source and
 * recipe. GNU visibility is selected by moon.pkg before any system header. */
#if defined(__linux__) && defined(__x86_64__) && \
    !defined(ACTQL_SCOPED_READ_ALLOCATOR) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
#define ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN 1
#endif
#include "moonbit.h"
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "component_domain_minimum.h"
#if defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
#if !defined(ACTQL_SCOPED_READ_ALLOCATOR) || defined(ACTQL_SCOPED_READ_PROVIDER)
#error "Imported bootstrap requires one selected scoped provider, never its source copy"
#endif
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.h"
#include "../../../packages/python-local-runtime/native/pre-root/owned_region.h"
#include "scoped_read.h"
#else
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
#ifndef ACTQL_SCOPED_READ_PROVIDER
#error "A scoped read build requires its exact copied provider source"
#endif
#include ACTQL_SCOPED_READ_PROVIDER
#else
#ifdef ACTQL_SCOPED_READ_PROVIDER
#error "A derived read provider requires the matching scoped runtime header"
#endif
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.c"
typedef struct actql_read_context actql_read_context;
#endif
#endif

#if defined(ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY)
/* Same provider's actual static records, co-counted inside the existing
 * command control envelope. This observes layout, never issues byte capacity. */
_Static_assert(sizeof(struct stock_file_record) == 24 && sizeof(stock_file_entry) == 8,
               "Selected Linux bundle stock-File layout");
_Static_assert(sizeof(stock_files) + sizeof(stock_file_entry) <= ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES,
               "Selected Linux bundle stock-File control page");
#endif

typedef struct {
    actql_owned_capacity *lease;
    int status;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    actql_read_context *control_context;
    bool control_attempted, control_user;
    size_t control_active;
#endif
} actql_bootstrap_backing;

typedef struct {
    actql_bootstrap_backing *owner;
    void *address;
    int status;
    bool domain_storage;
    bool working_selected;
} actql_bootstrap_extent;

static void keep_physical_custody(void *record) {
    /* A finalizer is not evidence of native retirement. */
    (void)record;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_page_bytes(void) {
    return (int64_t)sysconf(_SC_PAGESIZE);
}

#if defined(ACTQL_SCOPED_READ_ALLOCATOR) && defined(ACTQL_SCOPED_READ_PROVIDER) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
static bool component_minimum_add(size_t a, size_t b, size_t *out) {
    if (a > SIZE_MAX-b) return false;
    *out = a+b;
    return true;
}
static bool component_minimum_round(size_t bytes, size_t page, size_t *out) {
    size_t count;
    if (!round_pages(bytes, page, &count) || count > SIZE_MAX/page) return false;
    *out = count*page;
    return true;
}
static bool component_receiver_raw(size_t payload, size_t *out) {
    /* Exact pinned moonbit_make_external_object -> moonbit_malloc path. */
    size_t bytes;
    return payload != 0 &&
        component_minimum_add(payload, sizeof(void (*)(void *)), &bytes) &&
        component_minimum_add(bytes, sizeof(struct moonbit_object), out);
}
static bool component_domain_control(size_t capacity, size_t page, size_t *out) {
    if (!capacity || capacity > PTRDIFF_MAX || capacity % page) return false;
    size_t count = capacity/page;
    if (count > (SIZE_MAX-sizeof(actql_owned_capacity))/sizeof(struct extent)) return false;
    return component_minimum_round(sizeof(actql_owned_capacity)+count*sizeof(struct extent), page, out)
        && *out < capacity;
}
#endif

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_command_backing_control_necessary_bytes(
    int64_t bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR) && defined(ACTQL_SCOPED_READ_PROVIDER) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
    long page = sysconf(_SC_PAGESIZE);
    size_t control;
    if (bytes <= 0 || (uint64_t)bytes > PTRDIFF_MAX || page <= 0 ||
        !component_domain_control((size_t)bytes, (size_t)page, &control) || control > INT64_MAX)
        return -1;
    return (int64_t)control;
#else
    (void)bytes;
    return -1;
#endif
}

int64_t actql_bootstrap_component_domain_necessary_bytes(
    int64_t domain_bytes, int64_t heap_bytes, size_t library_payload,
    size_t database_payload, size_t maximum_path_bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR) && defined(ACTQL_SCOPED_READ_PROVIDER) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0 || domain_bytes <= 0 || heap_bytes < 4096 ||
        heap_bytes > INT32_MAX || (uint64_t)domain_bytes > PTRDIFF_MAX ||
        maximum_path_bytes == 0) return -1;
    size_t page = (size_t)selected_page, capacity = (size_t)domain_bytes;
    if (capacity % page != 0) return -1;
    size_t control, context, heap, text;
    if (!component_domain_control(capacity, page, &control) ||
        !component_minimum_round(sizeof(actql_read_context), page, &context) ||
        !component_minimum_round((size_t)heap_bytes, page, &heap) ||
        !component_minimum_round(maximum_path_bytes, page, &text)) return -1;
    size_t library, database;
    if (!component_receiver_raw(library_payload, &library) ||
        !component_receiver_raw(database_payload, &database)) return -1;
    bool library_small = library <= page/2, database_small = database <= page/2;
    size_t library_pages, database_pages, receivers;
    if (!component_minimum_round(library, page, &library_pages) ||
        !component_minimum_round(database, page, &database_pages)) return -1;
    if (library_small && database_small) {
        size_t a = read_heap_round(library), b = read_heap_round(database);
        size_t bytes = read_heap_round(sizeof(struct read_heap_page));
        if (!a || !b ||
            !component_minimum_add(bytes, read_heap_header(), &bytes) ||
            !component_minimum_add(bytes, a, &bytes) ||
            !component_minimum_add(bytes, read_heap_header(), &bytes) ||
            !component_minimum_add(bytes, b, &bytes)) return -1;
        if (!component_minimum_round(bytes, page, &receivers)) return -1;
    } else if (!component_minimum_add(library_pages, database_pages, &receivers)) return -1;
    size_t prebind, opened, total;
    /* sqlite_selected_component frees its File path immediately after dlopen,
     * BEFORE binding the heap. Do not add these mutually exclusive phases. */
    if (!component_minimum_add(library_pages, text, &prebind) ||
        !component_minimum_add(heap, receivers, &opened) ||
        !component_minimum_add(control, context, &total) ||
        !component_minimum_add(total, prebind > opened ? prebind : opened, &total) ||
        total > INT64_MAX) return -1;
    return (int64_t)total;
#else
    (void)domain_bytes; (void)heap_bytes; (void)library_payload;
    (void)database_payload; (void)maximum_path_bytes;
    return -1;
#endif
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_execution_domain_necessary_bytes(
    int64_t domain_bytes, int64_t payload_bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR) && defined(ACTQL_SCOPED_READ_PROVIDER) && \
    !defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
    long selected_page = sysconf(_SC_PAGESIZE);
    if (selected_page <= 0 || domain_bytes <= 0 || payload_bytes <= 0 ||
        (uint64_t)domain_bytes > PTRDIFF_MAX ||
        (uint64_t)payload_bytes > PTRDIFF_MAX) return -1;
    size_t page = (size_t)selected_page, control, context, payload, total;
    if (!component_domain_control((size_t)domain_bytes, page, &control) ||
        !component_minimum_round(sizeof(actql_read_context), page, &context) ||
        !component_minimum_round((size_t)payload_bytes, page, &payload) ||
        !component_minimum_add(control, context, &total) ||
        !component_minimum_add(total, payload, &total) || total > INT64_MAX)
        return -1;
    return (int64_t)total;
#else
    (void)domain_bytes; (void)payload_bytes;
    return -1;
#endif
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_acquire(int64_t bytes,
                                               int64_t generation,
                                               const unsigned char *recipe) {
    actql_bootstrap_backing *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
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
    memset(record, 0, sizeof(*record));
    record->status = ACTQL_OWNED_INVALID;
    if (fd >= 0 && bytes > 0 && (uint64_t)bytes <= SIZE_MAX && generation > 0) {
        record->status = actql_native_owned_acquire_fd(fd, (size_t)bytes,
                           (uint64_t)generation, recipe, &record->lease);
    }
    return record;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_control_bytes(actql_bootstrap_backing *record) {
    uint64_t bytes = 0;
    return actql_native_owned_control_bytes(record->lease, &bytes) == ACTQL_OWNED_OK &&
        bytes <= INT64_MAX ? (int64_t)bytes : -1;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_capacity_bytes(actql_bootstrap_backing *record) {
    uint64_t bytes = 0;
    return actql_native_owned_capacity_bytes(record->lease, &bytes) == ACTQL_OWNED_OK &&
        bytes <= INT64_MAX ? (int64_t)bytes : -1;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_growth_control_bytes(
    actql_bootstrap_backing *record, int64_t additional) {
    if (record == NULL || record->lease == NULL || additional <= 0 ||
        (uint64_t)additional > SIZE_MAX) return -1;
    uint64_t controls = 0;
    return actql_native_owned_growth_control_bytes(record->lease, (size_t)additional,
        &controls) == ACTQL_OWNED_OK && controls <= INT64_MAX ? (int64_t)controls : -1;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_grow(actql_bootstrap_backing *record,
    int64_t expected, int64_t additional) {
    if (record == NULL || expected <= 0 || additional <= 0 ||
        (uint64_t)expected > SIZE_MAX || (uint64_t)additional > SIZE_MAX)
        return ACTQL_OWNED_INVALID;
    uint64_t controls = 0;
    int status = actql_native_owned_grow(record->lease, (size_t)expected,
                                        (size_t)additional, &controls);
    return status == ACTQL_OWNED_OK ? (int64_t)controls : status;
}

MOONBIT_FFI_EXPORT int64_t actql_bootstrap_rounded_bytes(actql_bootstrap_backing *record,
                                                       int64_t bytes) {
    if (record->lease == NULL || bytes <= 0 || (uint64_t)bytes > SIZE_MAX) return -1;
    uint64_t rounded = 0;
    return actql_native_owned_rounded_bytes(record->lease, (size_t)bytes, &rounded) == ACTQL_OWNED_OK &&
        rounded <= INT64_MAX ? (int64_t)rounded : -1;
}

/* Fixed diagnostic DATA from the same already-entered backing. This cannot
 * enter a scope, acquire storage, return capacity or acknowledge cleanup. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_extent_work(
    actql_bootstrap_backing *record, int64_t *output, int32_t count) {
    if (record == NULL || record->lease == NULL || output == NULL || count != 5)
        return ACTQL_OWNED_INVALID;
    for (int32_t index = 0; index < count; index++)
        if (output[index] != 0) return ACTQL_OWNED_INVALID;
    uint64_t values[5] = {0};
    int status = actql_native_owned_extent_work(record->lease, values, 5);
    if (status != ACTQL_OWNED_OK) return status;
    for (int32_t index = 0; index < count; index++)
        if (values[index] > INT64_MAX) return ACTQL_OWNED_INVALID;
    for (int32_t index = 0; index < count; index++) output[index] = (int64_t)values[index];
    return ACTQL_OWNED_OK;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_claim(actql_bootstrap_backing *record,
                                               int64_t generation,
                                               const unsigned char *recipe) {
    return actql_native_owned_transfer(record->lease, (uint64_t)generation, recipe);
}

static void *allocate_extent(actql_bootstrap_backing *record,
                            int64_t bytes, bool domain_storage) {
    actql_bootstrap_extent *extent = moonbit_make_external_object(
        keep_physical_custody, sizeof(*extent));
    extent->owner = record;
    extent->address = NULL;
    extent->status = ACTQL_OWNED_INVALID;
    extent->domain_storage = domain_storage;
    extent->working_selected = false;
    if (bytes > 0 && (uint64_t)bytes <= SIZE_MAX) {
        extent->status = domain_storage
            ? actql_native_owned_allocate_in_process_domain(record->lease,
                                    (size_t)bytes, &extent->address)
            : actql_native_owned_allocate(record->lease,
                                    (size_t)bytes, 1, &extent->address);
    }
    return extent;
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_allocate(actql_bootstrap_backing *record,
                                                int64_t bytes) {
    return allocate_extent(record, bytes, false);
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_allocate_in_process_domain(
    actql_bootstrap_backing *record, int64_t bytes) {
    return allocate_extent(record, bytes, true);
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
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    /* The enclosing root cannot leave while its control Read still owns TLS.
     * Refuse before either scope is mutated so the caller can unwind normally. */
    if (record != NULL && record->control_active != 0) return ACTQL_OWNED_INVALID;
#endif
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

static void *lend_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    int64_t offset, int64_t length, int32_t writable, bool in_process) {
    actql_bootstrap_region *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->owner = owner;
    record->extent = extent;
    record->status = ACTQL_OWNED_INVALID;
    if (extent->owner == owner && extent->address != NULL &&
        offset >= 0 && length > 0 && (uint64_t)offset <= SIZE_MAX &&
        (uint64_t)length <= SIZE_MAX && (writable == 0 || writable == 1)) {
        if (extent->domain_storage) {
            if (in_process && offset == 0 && writable == 1)
                record->status = actql_native_owned_lend_in_process_domain(
                    owner->lease, extent->address, (size_t)length, &record->loan);
        } else record->status = (in_process ? actql_native_owned_lend_in_process_extent_range
                                     : actql_native_owned_lend_extent_range)(
            owner->lease, extent->address, (size_t)offset, (size_t)length,
            writable != 0, &record->loan);
    }
    return record;
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_lend_region(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    int64_t offset, int64_t length, int32_t writable) {
    return lend_region(owner, extent, offset, length, writable, false);
}

MOONBIT_FFI_EXPORT void *actql_bootstrap_lend_region_in_process(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    int64_t offset, int64_t length, int32_t writable) {
    return lend_region(owner, extent, offset, length, writable, true);
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

/* Same original parent mapping. This record owns only a local view, not
 * another mmap or an independently returnable physical holding. */
MOONBIT_FFI_EXPORT void *actql_bootstrap_view_region_in_process(
    actql_bootstrap_backing *owner, actql_bootstrap_extent *extent,
    actql_bootstrap_region *loan, int64_t payload_offset, int64_t payload_length) {
    actql_bootstrap_view *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    memset(record, 0, sizeof(*record));
    record->loan = loan;
    record->status = ACTQL_OWNED_INVALID;
    if (loan->owner == owner && loan->extent == extent && extent->owner == owner &&
        payload_offset >= 0 && payload_length > 0 &&
        (uint64_t)payload_offset <= SIZE_MAX && (uint64_t)payload_length <= SIZE_MAX) {
        if (extent->domain_storage) {
            if (payload_offset == 0 && (uint64_t)payload_length == loan->loan.extent.length)
                record->status = actql_native_owned_view_in_process_domain(
                    &loan->loan, &record->view);
        } else record->status = actql_native_owned_view_in_process_extent(&loan->loan,
            (size_t)payload_offset, (size_t)payload_length, &record->view);
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
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    /* Same domain carrier, not another external allocation or cleanup owner.
     * This derived layout needs its own real control/holding inventory. */
    actql_read_context *read_context;
    size_t read_active;
    bool read_attempted;
    bool read_user;
    bool read_prepare_scope;
#endif
} actql_bootstrap_domain;

#include "process_region.h"
#include "live_channel.h"

MOONBIT_FFI_EXPORT void *actql_bootstrap_acquire_domain(actql_bootstrap_view *view) {
    actql_bootstrap_domain *record = moonbit_make_external_object(
        keep_physical_custody, sizeof(*record));
    record->view = view;
    record->lease = NULL;
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    record->read_context = NULL;
    record->read_active = 0;
    record->read_attempted = false;
    record->read_user = false;
    record->read_prepare_scope = false;
#endif
    record->status = view->status == ACTQL_OWNED_OK
        ? actql_native_owned_acquire_extent_domain(&view->view, &record->lease)
        : view->status;
    return record;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_domain_status(actql_bootstrap_domain *record) {
    return record->status;
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_transfer_domain(actql_bootstrap_domain *record) {
    return actql_native_owned_transfer_original_domain(record->lease);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_enter_domain(actql_bootstrap_domain *record) {
    return actql_native_owned_enter(record->lease);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_leave_domain(actql_bootstrap_domain *record) {
    return actql_native_owned_leave(record->lease);
}

/* One atomic census of this exact already-entered domain. The original
 * provider retains controls and pending extents; no capacity or ACK is issued.
 * Validate the entire result before copying any caller-visible scalar. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_domain_inventory(
    actql_bootstrap_domain *record, int64_t *output, int32_t count) {
    if (record == NULL || record->lease == NULL || record->status != ACTQL_OWNED_OK ||
        output == NULL || count != 5) return ACTQL_OWNED_INVALID;
    for (int32_t index = 0; index < count; index++)
        if (output[index] != 0) return ACTQL_OWNED_INVALID;
    uint64_t values[16] = {0};
    int status = actql_native_owned_inventory(record->lease, values, 16);
    if (status != ACTQL_OWNED_OK) return status;
    for (int32_t index = 0; index < count; index++)
        if (values[index] > INT64_MAX) return ACTQL_OWNED_INVALID;
    for (int32_t index = 0; index < count; index++) output[index] = (int64_t)values[index];
    return ACTQL_OWNED_OK;
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

/* Capability, not a grant: nominal backing/current and Common use must precede
 * every physical read call. Stock builds refuse rather than silently fallback. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_supported(void) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    return 1;
#else
    return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_context_status(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record->read_prepare_scope) return ACTQL_OWNED_BUSY;
    return record->read_context != NULL && record->read_user
        ? ACTQL_OWNED_OK : ACTQL_OWNED_INVALID;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Same original physical scope only. A registered user or nominal active-phase
 * cell is not proof that this thread currently holds this exact context. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_context_entered(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL) return ACTQL_OWNED_INVALID;
    /* Reject an unbound thread before reading the original mutable scope.
     * The same Owner still excludes concurrent final retirement of its record. */
    actql_owned_capacity *lease = actql_native_owned_current();
    actql_read_context *context = actql_read_context_current();
    if (lease == NULL || context == NULL) return ACTQL_OWNED_INVALID;
    if (lease != record->lease || context != record->read_context ||
        record->read_prepare_scope || !record->read_user || record->read_active == 0)
        return ACTQL_OWNED_INVALID;
    return ACTQL_OWNED_OK;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* This original's physical scope state, not proof that every other scope is
 * clear. The nominal Owner checks current/lifetime and excludes concurrent
 * retirement. A different active frame never counts as this original entered. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_context_scope(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || record->read_context == NULL || !record->read_user ||
        record->read_prepare_scope) return ACTQL_OWNED_INVALID;
    actql_read_context *context = actql_read_context_current();
    actql_owned_capacity *lease = actql_native_owned_current();
    if (record->read_active == 0 && context != record->read_context &&
        lease != record->lease) return 0;
    if (record->read_active != 0 && context == record->read_context &&
        lease == record->lease) return 1;
    return ACTQL_OWNED_BUSY;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Same-original cleanup can outlive the original retained Read user: that user
 * may already have returned while escaped aliases still keep try_close BUSY.
 * Observe the retained context/frame only; issue no user, current or ACK. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_context_cleanup_scope(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || !record->read_attempted ||
        record->read_context == NULL || record->read_prepare_scope)
        return ACTQL_OWNED_INVALID;
    actql_read_context *context = actql_read_context_current();
    actql_owned_capacity *lease = actql_native_owned_current();
    if (record->read_active == 0 && context != record->read_context &&
        lease != record->lease) return 0;
    if (record->read_active != 0 && context == record->read_context &&
        lease == record->lease) return 1;
    return ACTQL_OWNED_BUSY;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* A closed metadata projection of the same retained original after failed
 * close. It does not enter/leave, return a user or acknowledge retirement. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_cleanup_thread_current(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || !record->read_attempted || record->read_context == NULL ||
        record->read_prepare_scope) return ACTQL_OWNED_INVALID;
    return actql_read_context_cleanup_thread_current(record->read_context);
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_cleanup_snapshot(
    actql_bootstrap_domain *record, int64_t *output, int32_t count) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || output == NULL || count != 16 ||
        !record->read_attempted || record->read_context == NULL ||
        record->read_prepare_scope) return ACTQL_OWNED_INVALID;
    for (int32_t index = 0; index < count; index++)
        if (output[index] != 0) return ACTQL_OWNED_INVALID;
    uint64_t values[16] = {0};
    int status = actql_read_context_cleanup_snapshot(record->read_context, values, 16);
    if (status != ACTQL_OWNED_OK) return status;
    for (int32_t index = 0; index < count; index++) output[index] = (int64_t)values[index];
    return ACTQL_OWNED_OK;
#else
    (void)record; (void)output; (void)count;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Actual selected public runtime-header facts only. They are neither a
 * complete managed-object inventory nor a capacity/initial-service issuer. */
MOONBIT_FFI_EXPORT int64_t actql_bootstrap_managed_value_layout(int32_t field) {
    switch (field) {
    case 0: return (int64_t)sizeof(struct moonbit_object);
    case 1: return (int64_t)sizeof(uint16_t);
    case 2: return (int64_t)sizeof(uint16_t); /* Selected String terminator. */
    case 3: return (int64_t)sizeof(struct moonbit_valtype_array_header);
    case 4: return (int64_t)sizeof(void *);
    default: return -1;
    }
}

/* Registration control is prepared before any Read/owned scope on this
 * thread. This observes only the same original's unentered state: it does not
 * enter a context, allocate control or acknowledge any owner retirement. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_read_context_unentered(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || actql_read_context_current() != NULL ||
        actql_native_owned_current() != NULL) return ACTQL_OWNED_INVALID;
    if (record->read_context == NULL || !record->read_user ||
        record->read_prepare_scope || record->read_active != 0)
        return ACTQL_OWNED_INVALID;
    return ACTQL_OWNED_OK;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Same original domain, selected before its first Read allocation. A physical
 * ceiling includes allocator control and every occupied/pending extent; it is
 * not a new reservation, a smaller mapping or a parent retirement ACK. */
static int32_t prepare_read_context_original(actql_bootstrap_domain *record,
                                             int64_t ceiling, bool bounded) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || record->read_attempted || record->lease == NULL)
        return ACTQL_OWNED_INVALID;
    record->read_attempted = true;
    int status = actql_native_owned_enter(record->lease);
    if (status != ACTQL_OWNED_OK) return status;
    record->read_prepare_scope = true;
    if (bounded) {
        /* Even an invalid original selection consumes this attempt. */
        size_t bytes = ceiling > 0 && (uint64_t)ceiling <= SIZE_MAX
            ? (size_t)ceiling : 0;
        status = actql_native_owned_bound_allocations(record->lease, bytes);
    }
    if (status == ACTQL_OWNED_OK)
        status = actql_read_context_create(record->lease, &record->read_context);
    if (status == ACTQL_OWNED_OK) {
        status = actql_read_context_retain(record->read_context);
        if (status == ACTQL_OWNED_OK) record->read_user = true;
    }
    int left = actql_native_owned_leave(record->lease);
    if (left == ACTQL_OWNED_OK) record->read_prepare_scope = false;
    return status == ACTQL_OWNED_OK ? left : status;
#else
    (void)record; (void)ceiling; (void)bounded;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_prepare_read_context(
    actql_bootstrap_domain *record) {
    return prepare_read_context_original(record, 0, false);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_prepare_bounded_read_context(
    actql_bootstrap_domain *record, int64_t ceiling) {
    return prepare_read_context_original(record, ceiling, true);
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_enter_read_context(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record->read_context == NULL || record->read_prepare_scope ||
        record->read_active == SIZE_MAX) return ACTQL_OWNED_INVALID;
    int status = actql_native_owned_enter(record->lease);
    if (status != ACTQL_OWNED_OK) return status;
    /* Normal Common entry already requires read_user/current. Once that
     * original user has returned, only its existing stopped cleanup caller can
     * reach this same carrier. Do not manufacture a replacement retained user. */
    status = record->read_user ? actql_read_context_enter(record->read_context)
                              : actql_read_context_enter_cleanup(record->read_context);
    if (status != ACTQL_OWNED_OK) {
        int left = actql_native_owned_leave(record->lease);
        if (left != ACTQL_OWNED_OK) record->read_prepare_scope = true;
        return status;
    }
    record->read_active++;
    return ACTQL_OWNED_OK;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_leave_read_context(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record->read_active == 0) return ACTQL_OWNED_INVALID;
    int status = actql_read_context_leave(record->read_context);
    if (status != ACTQL_OWNED_OK) return status;
    record->read_active--;
    status = actql_native_owned_leave(record->lease);
    if (status != ACTQL_OWNED_OK) record->read_prepare_scope = true;
    return status;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Cleanup of a failed entry only: confirm that THIS original never retained
 * an entered Read frame. A recorded failed unwind may return only its own
 * owned scope. No context/user/extent is released and no current is issued. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_finish_failed_read_entry_cleanup(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record == NULL || !record->read_attempted || record->lease == NULL ||
        record->read_context == NULL || record->read_active != 0)
        return ACTQL_OWNED_INVALID;
    if (actql_read_context_current() != NULL) return ACTQL_OWNED_BUSY;
    if (record->read_prepare_scope) {
        if (actql_native_owned_current() != record->lease)
            return ACTQL_OWNED_BUSY;
        int status = actql_native_owned_leave(record->lease);
        if (status != ACTQL_OWNED_OK) return status;
        record->read_prepare_scope = false;
    }
    return actql_native_owned_current() == NULL &&
        actql_read_context_current() == NULL ? ACTQL_OWNED_OK : ACTQL_OWNED_BUSY;
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Borrowed only while the existing Native caller holds its active scope. The
 * filesystem constructor retains it before allocating/FD access. No new TLS,
 * pointer transport, permission lookup or context adoption is introduced. */
MOONBIT_FFI_EXPORT actql_read_context *actql_bootstrap_current_read_context(void) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    return actql_read_context_current();
#else
    return NULL;
#endif
}

MOONBIT_FFI_EXPORT int32_t actql_bootstrap_close_read_context(
    actql_bootstrap_domain *record) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    if (record->read_active != 0) return ACTQL_OWNED_BUSY;
    if (record->read_prepare_scope) {
        int left = actql_native_owned_leave(record->lease);
        if (left != ACTQL_OWNED_OK) return left;
        record->read_prepare_scope = false;
    }
    if (record->read_context == NULL) return ACTQL_OWNED_OK;
    if (record->read_user) {
        int status = actql_read_context_release_after_owner_ack(record->read_context);
        if (status != ACTQL_OWNED_OK) return status;
        record->read_user = false;
    }
    return actql_read_context_try_close(&record->read_context);
#else
    (void)record;
    return ACTQL_OWNED_INVALID;
#endif
}

/* Whole current physical frame only. Leaving one nesting level is not this
 * observation; valid-pointer NULL cannot substitute raw TLS/depth checks. */
MOONBIT_FFI_EXPORT int32_t actql_bootstrap_control_scope_clear(void) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
    return actql_read_context_control_scope_clear();
#else
    return actql_native_owned_control_scope_clear();
#endif
}

#include "root_control.inc"
#include "working_origin.inc"
#include "backed_domain_growth.inc"

#include "command_platform_unavailable.h"
