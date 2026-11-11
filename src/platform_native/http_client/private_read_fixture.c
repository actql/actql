/* Focused C provider/caller checks; no Host, installed runtime or network. */
#define main original_scoped_fixture_main
#include SCOPED_FIXTURE
#undef main
#include COMMAND_UNAVAILABLE
void *actql_bootstrap_current_read_context(void) { return actql_read_context_current(); }
#include HTTP_OWNER

static bool small_native_cells(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    context_enter(lease, read);
    size_t before = lease->occupied_pages;
    void *cells[4000];
    for (size_t i = 0; i < 4000; i++) {
        cells[i] = actql_http_component_allocate(read, lease, 8);
        assert(cells[i] && (uintptr_t)cells[i] % _Alignof(max_align_t) == 0);
        memset(cells[i], 77, 8);
    }
    size_t pages = lease->occupied_pages - before;
    assert(pages < 32); /* 4000 private objects do not demand 4000 pages. */
    for (size_t i = 0; i < 4000; i++) {
        assert(((unsigned char *)cells[i])[7] == 77);
        actql_http_component_retire(read, lease, cells[i]);
    }
    assert(lease->occupied_pages == before);
    context_leave(lease, read);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    printf("{\"case\":\"same-read-small-native-cells\",\"allocations\":4000,\"physicalPages\":%zu,\"passed\":1}\n", pages);
    return true;
}

static bool native_provenance_and_file(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    assert(actql_native_private_scoped_allocate(1) == NULL);
    context_enter(lease, read);
    void *native = actql_native_private_scoped_callocate(7, 13);
    void *managed = actql_native_moon_scoped_allocate(91);
    void *file = actql_native_file_scoped_allocate(91);
    assert(native && managed && file);
    for (size_t i = 0; i < 91; i++) assert(((unsigned char *)native)[i] == 0);
    assert(actql_native_private_scoped_callocate(SIZE_MAX, 2) == NULL);
    assert(actql_native_private_scoped_allocate(SIZE_MAX) == NULL);
    assert(actql_native_private_scoped_contains_allocation(read, lease, native, 91) == 0);
    assert(actql_native_private_scoped_contains_allocation(read, lease, native, 92) != 0);
    assert(actql_native_private_scoped_contains_allocation(read, lease, (char *)native+1, 1) != 0);
    assert(actql_native_private_scoped_contains_allocation(read, lease, managed, 1) != 0);
    assert(actql_native_private_scoped_contains_allocation(read, lease, file, 1) != 0);
    assert(release_read_bytes(native, READ_MANAGED) == ACTQL_OWNED_INVALID);
    assert(release_read_bytes(native, READ_FILE) == ACTQL_OWNED_INVALID);
    assert(actql_native_private_scoped_free(managed) == ACTQL_OWNED_INVALID);
    assert(actql_native_private_scoped_free(file) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_protect(lease, native, 0, lease->page_size, PROT_READ) != 0);
    assert(actql_native_owned_protect(lease, file, 0, lease->page_size, PROT_READ) == 0);
    assert(actql_native_owned_protect(lease, file, 0, lease->page_size, PROT_READ|PROT_WRITE) == 0);
    context_leave(lease, read);
    assert(actql_native_private_scoped_contains_allocation(read, lease, native, 1) != 0);
    /* Free after leave follows that exact original, without a current grant. */
    assert(actql_native_private_scoped_free(native) == 0);
    actql_native_moon_scoped_free(managed);
    actql_native_file_scoped_free(file);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    return true;
}

static bool native_replacement_overlap(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    context_enter(lease, read);
    size_t before = lease->occupied_pages;
    unsigned char *original = actql_http_component_allocate(read, lease, 20000);
    assert(original); memset(original, 93, 20000);
    assert(actql_http_component_reallocate(read, lease, original, lease->length) == NULL);
    for (size_t i=0; i<20000; i++) assert(original[i] == 93);
    unsigned char *grown = actql_http_component_reallocate(read, lease, original, 50000);
    assert(grown && grown != original);
    for (size_t i=0; i<20000; i++) assert(grown[i] == 93);
    assert(actql_native_private_scoped_contains_allocation(read, lease,
        (actql_http_component_allocation *)grown-1, 50000+sizeof(actql_http_component_allocation)) == 0);
    assert(actql_native_owned_seal_readonly(lease, (actql_http_component_allocation *)grown-1) != 0);
    actql_http_component_retire(read, lease, grown);
    assert(lease->occupied_pages == before);
    context_leave(lease, read);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    return true;
}

static bool native_current_and_fork(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    actql_read_context *other = context_new(lease);
    assert(actql_read_context_retain(other) == 0);
    context_enter(lease, read);
    void *original = actql_native_private_scoped_allocate(32);
    assert(original); memset(original, 31, 32);
    pid_t pid = fork(); assert(pid >= 0);
    if (pid == 0) {
        assert(actql_native_private_scoped_allocate(16) == NULL);
        assert(actql_native_private_scoped_free(original) == ACTQL_OWNED_INVALID);
        _exit(0);
    }
    assert(child_status(pid,0));
    context_leave(lease, read);
    context_enter(lease, other);
    assert(actql_native_private_scoped_contains_allocation(other, lease, original, 1) != 0);
    assert(actql_http_component_allocate(read, lease, 12) == NULL);
    assert(((unsigned char *)original)[0] == 31);
    context_leave(lease, other);
    assert(actql_native_private_scoped_free(original) == 0);
    assert(actql_read_context_release_after_owner_ack(other) == 0);
    assert(actql_read_context_try_close(&other) == 0);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    return true;
}

static bool native_failed_retirement(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    context_enter(lease, read);
    void *original = actql_native_private_scoped_allocate(24);
    assert(original);
    size_t index = ((uintptr_t)original-(uintptr_t)lease)/lease->page_size;
    size_t occupied = lease->occupied_pages;
    retirement_target = (unsigned char *)lease + index*lease->page_size;
    retirement_failures = 2;
    assert(actql_native_private_scoped_free(original) == ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(lease->occupied_pages == occupied && lease->extents[index].retired);
    context_leave(lease, read);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    assert(actql_read_context_try_close(&read) == ACTQL_OWNED_PHYSICAL_FAILURE && read);
    assert(lease->occupied_pages == occupied);
    retirement_target = NULL;
    finish(&lease, &read);
    return true;
}

/* A large live block leaves a free tail in an interior physical page. Both
 * allocation and free must resolve the SAME original multi-page extent. */
static bool native_multi_page_slots(void) {
    actql_owned_capacity *lease = lease_new();
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    context_enter(lease, read);
    size_t before = lease->occupied_pages;
    unsigned char *large = actql_native_private_scoped_allocate(3 * lease->page_size);
    assert(large); memset(large, 51, 3 * lease->page_size);
    unsigned char *small = actql_native_private_scoped_allocate(24);
    assert(small && (uintptr_t)small / lease->page_size > (uintptr_t)large / lease->page_size);
    assert(actql_native_private_scoped_contains_allocation(read, lease, small, 24) == 0);
    assert(release_read_bytes(small, READ_MANAGED) == ACTQL_OWNED_INVALID);
    assert(actql_native_owned_contains_live_span(lease, small, 24) == 0);
    memset(small, 62, 24);
    context_leave(lease, read);
    assert(actql_native_private_scoped_free(small) == 0);
    for (size_t i=0;i<3*lease->page_size;i++) assert(large[i] == 51);
    assert(actql_native_private_scoped_free(large) == 0);
    assert(lease->occupied_pages == before);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    puts("{\"case\":\"native-interior-page-slot-original\",\"executed\":1,\"passed\":1,\"physicalReadClosed\":true}");
    return true;
}

/* One changed-path TLS case uses the production-sized Read and full trust
 * bundle. It is a C component diagnostic, not an installed Resident/Host. */
static int full_ca_transport(int argc, char **argv) {
    assert(argc == 6);
    actql_owned_capacity *lease = NULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    assert(actql_native_owned_acquire(256 * 1024 * 1024, 16 * 1024 * 1024 / page, recipe, &lease) == 0);
    assert(actql_native_owned_transfer(lease, 16 * 1024 * 1024 / page, recipe) == 0);
    actql_read_context *read = context_new(lease);
    assert(actql_read_context_retain(read) == 0);
    context_enter(lease, read);
    moonbit_bytes_t path = moonbit_make_bytes_raw((int32_t)strlen(argv[2]));
    memcpy(path, argv[2], strlen(argv[2]));
    actql_native_http_library *library = actql_native_http_load_library_with_custody(path, (int32_t)strlen(argv[2]), 256);
    assert(library && !library->load_failed && library->tls_owned && library->tls_api->abi == 3);
    actql_native_http_client *client = actql_native_http_create_authenticated_client(library,
        (moonbit_bytes_t)argv[4], (int32_t)strlen(argv[4]), NULL, 0, NULL, 0,
        (moonbit_bytes_t)argv[5], (int32_t)strlen(argv[5]), 4096, 5000, 15000);
    assert(client && actql_native_http_client_ready(client));
    int result = actql_native_http_client_post_json(client,
        (moonbit_bytes_t)argv[3], (int32_t)strlen(argv[3]), (moonbit_bytes_t)"{}", 2);
    printf("{\"stage\":\"full-ca-native-http\",\"result\":%d,\"status\":%ld,\"peakPages\":%zu,\"pageBytes\":%zu}\n",
        result,client->status,lease->peak_occupied_pages,lease->page_size);
    fflush(stdout);
    assert(result == 0 && client->status == 204);
    assert(actql_native_http_client_close_checked(client) == 0);
    moonbit_decref(client);
    assert(actql_native_http_library_close_checked(library) == 0);
    moonbit_decref(library); moonbit_decref(path);
    context_leave(lease, read);
    assert(actql_read_context_release_after_owner_ack(read) == 0);
    finish(&lease, &read);
    puts("{\"case\":\"full-ca-http-private-read\",\"passed\":1,\"physicalReadClosed\":true,\"wholeHostAck\":false}");
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1],"--full-ca-only") == 0) return full_ca_transport(argc,argv);
    if (argc == 2 && strcmp(argv[1],"--multi-page-slots-only") == 0) return native_multi_page_slots() ? 0 : 1;
    assert(argc == 1);
    struct {const char *name; bool (*run)(void);} cases[] = {
        {"small-native-cells",small_native_cells},
        {"native-family-current-and-generic-file",native_provenance_and_file},
        {"native-full-replacement-overlap",native_replacement_overlap},
        {"native-original-current-and-fork",native_current_and_fork},
        {"native-retirement-failure-stays-pending",native_failed_retirement}
    };
    size_t stock_before = stock_file_allocations;
    for (size_t i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
        assert(cases[i].run());
        printf("{\"case\":\"%s\",\"passed\":1}\n",cases[i].name);
    }
    assert(stock_file_allocations == stock_before);
    puts("{\"executed\":5,\"passed\":5,\"failed\":0,\"stockFallback\":0,\"publicE2E\":0}");
    return 0;
}
