#include "owned_domain_borrow.h"

/* Caller storage belongs to the separate finite control envelope. It is not
 * allocated from the delegated payload or charged as another arena reserve. */
struct actql_domain_borrow_record {
    struct actql_domain_borrow_record *original;
    pid_t process;
    actql_owned_extent_view view;
    actql_owned_capacity *lease;
    int status;
    bool closing;
    bool closed;
};

size_t actql_native_domain_borrow_storage_bytes(void) {
    return sizeof(struct actql_domain_borrow_record);
}
size_t actql_native_domain_borrow_storage_alignment(void) {
    return _Alignof(struct actql_domain_borrow_record);
}
static struct actql_domain_borrow_record *original_domain_record(void *storage) {
    if (storage == NULL || (uintptr_t)storage % _Alignof(struct actql_domain_borrow_record) != 0)
        return NULL;
    struct actql_domain_borrow_record *record = storage;
    return record->original == record && record->process == getpid() ? record : NULL;
}

int actql_native_domain_borrow_open(void *storage, size_t bytes, int fd,
    const unsigned char recipe[32], const int64_t material[15]) {
    if (storage == NULL || bytes != sizeof(struct actql_domain_borrow_record) ||
        (uintptr_t)storage % _Alignof(struct actql_domain_borrow_record) != 0 ||
        recipe == NULL || material == NULL || fd < 0)
        return ACTQL_OWNED_INVALID;
    struct actql_domain_borrow_record *record = storage;
    if (record->original != NULL) return ACTQL_OWNED_INVALID;
    record->original = record;
    record->process = getpid();
    record->status = ACTQL_OWNED_INVALID;
    /* Check ABI encoding only; the existing Core supplied bounds and quota.
     * This physical port never reconstructs permission from these numbers. */
    for (size_t i = 0; i < 15; i++)
        if (material[i] < 0 || (i >= 3 && i <= 7 && (uint64_t)material[i] > SIZE_MAX))
            return ACTQL_OWNED_INVALID;
    if (material[0] == 0 || material[8] != 1) return ACTQL_OWNED_INVALID;
    actql_owned_extent_reference extent = {
        .generation = (uint64_t)material[0], .device = (uint64_t)material[1],
        .inode = (uint64_t)material[2], .capacity = (size_t)material[3],
        .offset = (size_t)material[4], .length = (size_t)material[5], .writable = true
    };
    memcpy(extent.recipe, recipe, sizeof(extent.recipe));
    record->status = actql_native_owned_map_extent_payload(fd, &extent,
        (size_t)material[6], (size_t)material[7], &record->view);
    if (record->status == ACTQL_OWNED_OK)
        record->status = actql_native_owned_borrow_extent_domain(&record->view, &record->lease);
    return record->status;
}

int actql_native_domain_borrow_status(void *storage) {
    struct actql_domain_borrow_record *record = original_domain_record(storage);
    if (record == NULL || record->closed || record->closing) return ACTQL_OWNED_INVALID;
    return record->status;
}
int actql_native_domain_borrow_enter(void *storage) {
    struct actql_domain_borrow_record *record = original_domain_record(storage);
    if (record == NULL || record->closed || record->closing || record->lease == NULL)
        return ACTQL_OWNED_INVALID;
    if (record->status != ACTQL_OWNED_OK) return record->status;
    return actql_native_owned_enter(record->lease);
}
int actql_native_domain_borrow_leave(void *storage) {
    struct actql_domain_borrow_record *record = original_domain_record(storage);
    if (record == NULL || record->closed || record->lease == NULL) return ACTQL_OWNED_INVALID;
    return actql_native_owned_leave(record->lease);
}
int actql_native_domain_borrow_pointer(void *storage, actql_owned_capacity **out) {
    struct actql_domain_borrow_record *record = original_domain_record(storage);
    if (record == NULL || out == NULL || *out != NULL || record->closed || record->closing ||
        record->status != ACTQL_OWNED_OK || record->lease == NULL) return ACTQL_OWNED_INVALID;
    *out = record->lease;
    return ACTQL_OWNED_OK;
}
int actql_native_domain_borrow_close(void *storage) {
    struct actql_domain_borrow_record *record = original_domain_record(storage);
    if (record == NULL) return ACTQL_OWNED_INVALID;
    if (record->closed) return ACTQL_OWNED_OK;
    record->closing = true;
    if (record->lease != NULL) {
        int status = actql_native_owned_return_extent_domain_borrow(&record->view, &record->lease);
        if (status != ACTQL_OWNED_OK) return status;
    }
    if (record->view.original != NULL) {
        int status = actql_native_owned_close_extent_view(&record->view);
        if (status != ACTQL_OWNED_OK) return status;
    }
    record->closed = true;
    return ACTQL_OWNED_OK;
}
