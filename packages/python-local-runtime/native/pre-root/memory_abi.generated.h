/* Generated from existing C headers and checked Rust forwarders. */
#ifndef ACTQL_PRIVATE_MEMORY_ABI_GENERATED_H
#define ACTQL_PRIVATE_MEMORY_ABI_GENERATED_H
#include "owned_capacity.h"
#include "owned_domain_borrow.h"
#include "owned_thread.h"
int actql_native_domain_borrow_capacity(void * storage, uint64_t * out);
int actql_native_domain_borrow_claim_holding(void * storage, actql_owned_capacity ** slot);
int actql_native_domain_borrow_close(void * storage);
int actql_native_domain_borrow_close_holding(void * storage, actql_owned_capacity ** slot);
int actql_native_domain_borrow_contains_live_span(void * storage, const void * address, size_t bytes);
int actql_native_domain_borrow_enter(void * storage);
int actql_native_domain_borrow_leave(void * storage);
int actql_native_domain_borrow_open(void * storage, size_t bytes, int fd, const unsigned char * recipe, const int64_t * material);
int actql_native_domain_borrow_pointer(void * storage, actql_owned_capacity ** out);
int actql_native_domain_borrow_span_offset(void * storage, actql_owned_capacity * holding, const void * address, size_t bytes, uint64_t * out);
int actql_native_domain_borrow_status(void * storage);
size_t actql_native_domain_borrow_storage_alignment(void);
size_t actql_native_domain_borrow_storage_bytes(void);
int actql_native_domain_borrow_transfer_holding(void * storage, actql_owned_capacity * holding, uint64_t generation, const unsigned char * recipe);
int actql_native_owned_acquire(size_t capacity, uint64_t generation, const unsigned char * recipe, actql_owned_capacity ** out);
int actql_native_owned_allocate(actql_owned_capacity * lease, size_t bytes, size_t alignment, void ** out);
int actql_native_owned_bound_allocations(actql_owned_capacity * lease, size_t bytes);
int actql_native_owned_capacity_bytes(actql_owned_capacity * lease, uint64_t * out);
int actql_native_owned_capture_image_fd(actql_owned_capacity * lease, int fd, size_t expected_bytes, size_t maximum_bytes, const unsigned char * digest, void ** out);
int actql_native_owned_contains_live_rust_span(actql_owned_capacity * lease, const void * address, size_t bytes);
int actql_native_owned_contains_live_span(actql_owned_capacity * lease, const void * address, size_t bytes);
int actql_native_owned_control_bytes(actql_owned_capacity * lease, uint64_t * out);
int actql_native_owned_control_scope_clear(void);
actql_owned_capacity * actql_native_owned_current(void);
int actql_native_owned_enter(actql_owned_capacity * lease);
int actql_native_owned_extent_work(actql_owned_capacity * lease, uint64_t * out, size_t count);
int actql_native_owned_grow(actql_owned_capacity * lease, size_t expected_bytes, size_t additional_bytes, uint64_t * control_bytes);
int actql_native_owned_growth_control_bytes(actql_owned_capacity * lease, size_t bytes, uint64_t * out);
int actql_native_owned_growth_for_payload_bytes(actql_owned_capacity * lease, size_t payload_bytes, uint64_t * out);
int actql_native_owned_inventory(actql_owned_capacity * lease, uint64_t * out, size_t count);
int actql_native_owned_leave(actql_owned_capacity * lease);
int actql_native_owned_protect(actql_owned_capacity * lease, void * allocation, size_t offset, size_t length, int protection);
int actql_native_owned_retire(actql_owned_capacity * lease, void * allocation);
int actql_native_owned_rounded_bytes(actql_owned_capacity * lease, size_t bytes, uint64_t * out);
int actql_native_owned_rust_allocate(actql_owned_capacity * lease, size_t bytes, size_t alignment, void ** out, uint64_t * token);
int actql_native_owned_rust_retire(actql_owned_capacity * lease, void * allocation, uint64_t token);
int actql_native_owned_seal_readonly(actql_owned_capacity * lease, void * allocation);
size_t actql_native_owned_thread_control_alignment(void);
size_t actql_native_owned_thread_control_bytes(void);
int actql_native_owned_thread_join(actql_owned_capacity * lease, void * storage);
int actql_native_owned_thread_start(actql_owned_capacity * lease, void * storage, size_t storage_bytes, actql_owned_thread_entry entry, void * argument);
int actql_native_owned_thread_start_configured(actql_owned_capacity * lease, void * storage, size_t storage_bytes, const void * attributes, actql_owned_thread_entry entry, void * argument);
int actql_native_owned_transfer(actql_owned_capacity * lease, uint64_t generation, const unsigned char * recipe);
int actql_native_owned_transfer_original_domain(actql_owned_capacity * lease);
int actql_native_owned_try_close(actql_owned_capacity ** lease);
int actql_owned_acquire(size_t capacity, uint64_t generation, const unsigned char * recipe, actql_owned_capacity ** out);
int actql_owned_allocate(actql_owned_capacity * lease, size_t bytes, size_t alignment, void ** out);
int actql_owned_capacity_bytes(actql_owned_capacity * lease, uint64_t * out);
int actql_owned_capture_image_fd(actql_owned_capacity * lease, int fd, size_t expected_bytes, size_t maximum_bytes, const unsigned char * digest, void ** out);
int actql_owned_contains_live_span(actql_owned_capacity * lease, const void * address, size_t bytes);
actql_owned_capacity * actql_owned_current(void);
int actql_owned_enter(actql_owned_capacity * lease);
int actql_owned_leave(actql_owned_capacity * lease);
int actql_owned_protect(actql_owned_capacity * lease, void * allocation, size_t offset, size_t length, int protection);
int actql_owned_retire(actql_owned_capacity * lease, void * allocation);
int actql_owned_rust_allocate(actql_owned_capacity * lease, size_t bytes, size_t alignment, void ** out, uint64_t * token);
int actql_owned_rust_retire(actql_owned_capacity * lease, void * allocation, uint64_t token);
int actql_owned_seal_readonly(actql_owned_capacity * lease, void * allocation);
int actql_owned_transfer(actql_owned_capacity * lease, uint64_t generation, const unsigned char * recipe);
int actql_owned_try_close(actql_owned_capacity ** lease);
#endif
