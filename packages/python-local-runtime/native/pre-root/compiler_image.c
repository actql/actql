/* Private compiler on the same source-bound inherited Native domain on the original inherited Native domain.
 * Trusted parent preparation must retain its original child/frame/region and
 * fund this separate control storage before launch. Arguments are DATA only;
 * FD4 is the same captured original, never a reason to acquire another root. */
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "owned_domain_borrow.h"
#include "compiler_configuration.generated.h"
#include "compiler_module_abi.h"

static int hex(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

/* Compiler-call custody only. The original process Owner retains all runtime
 * statics and the same region through typed stop; these slots issue no grant. */
struct compilation {
    actql_owned_capacity *owner;
    int module_fd;
    int output_fd;
    bool fd_close_pending;
    bool config_attempted;
    bool engine_attempted;
    bool module_attempted;
    void *module_bytes;
    wasm_config_t *config;
    wasmtime_pooling_allocation_config_t *pool;
    wasm_engine_t *engine;
    wasmtime_module_t *module;
    wasmtime_error_t *error;
    wasm_byte_vec_t image;
};

static int close_descriptor(int *slot, bool *pending) {
    if (*slot < 0) return 0;
    if (*pending) return -1;
    *pending = true;
    if (close(*slot) != 0) return -1;
    *slot = -1;
    *pending = false;
    return 0;
}

static int close_compilation(struct compilation *call) {
    if (actql_native_owned_current() != call->owner) return -1;
    if (call->image.data != NULL) {
        wasm_byte_vec_delete(&call->image);
        call->image = (wasm_byte_vec_t){0};
    }
    if (call->error != NULL) {
        wasmtime_error_delete(call->error);
        call->error = NULL;
    }
    if (call->module != NULL) {
        wasmtime_module_delete(call->module);
        call->module = NULL;
    }
    if (call->engine != NULL) {
        wasm_engine_delete(call->engine);
        call->engine = NULL;
    }
    if (call->pool != NULL) {
        wasmtime_pooling_allocation_config_delete(call->pool);
        call->pool = NULL;
    }
    if (call->config != NULL) {
        wasm_config_delete(call->config);
        call->config = NULL;
    }
    if (call->module_bytes != NULL) {
        int result = actql_native_owned_retire(call->owner, call->module_bytes);
        if (result != ACTQL_OWNED_OK) return result;
        call->module_bytes = NULL;
    }
    /* A lost/failed close is sticky in this call. Process retirement may later
     * discharge its descriptor responsibility; this code never repeats close. */
    if (close_descriptor(&call->module_fd, &call->fd_close_pending) != 0) return -1;
    return close_descriptor(&call->output_fd, &call->fd_close_pending);
}

static int compile_original(struct compilation *call, const char *module_path,
                            const char *output_path, size_t *image_bytes) {
    if (actql_native_owned_current() != call->owner) return 1;
    call->module_fd = open(module_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (call->module_fd < 0) return 2;
    struct stat original;
    if (fstat(call->module_fd, &original) != 0 || !S_ISREG(original.st_mode) ||
        original.st_size <= 0 || (uint64_t)original.st_size > 32 * UINT64_C(1024) * 1024)
        return 3;
    unsigned char digest[32];
    const char *expected = ACTQL_COMPILER_MODULE_SHA256;
    if (strlen(expected) != 64) return 4;
    for (size_t i = 0; i < 32; i++) {
        int high = hex((unsigned char)expected[2 * i]);
        int low = hex((unsigned char)expected[2 * i + 1]);
        if (high < 0 || low < 0) return 4;
        digest[i] = (unsigned char)(16 * high + low);
    }
    int capture = actql_native_owned_capture_image_fd(call->owner, call->module_fd,
        (size_t)original.st_size, 32 * 1024 * 1024, digest, &call->module_bytes);
    if (capture != ACTQL_OWNED_OK) return 5;
    if (close_descriptor(&call->module_fd, &call->fd_close_pending) != 0) return 6;
    /* Exact source/module bytes and original scope precede the first Config.
     * No alternate module, JIT fallback, Store or instance is constructed. */
    call->config_attempted = true;
    call->config = wasm_config_new();
    if (call->config == NULL) return 7;
    call->pool = wasmtime_pooling_allocation_config_new();
    if (call->pool == NULL) return 8;
    call->error = actql_compiler_configure(call->config, call->pool);
    if (call->error != NULL) return 9;
    wasmtime_pooling_allocation_config_delete(call->pool);
    call->pool = NULL;
    /* This official C API consumes the original Config at entry. */
    wasm_config_t *consumed = call->config;
    call->config = NULL;
    call->engine_attempted = true;
    call->engine = wasm_engine_new_with_config(consumed);
    if (call->engine == NULL) return 10;
    call->module_attempted = true;
    call->error = wasmtime_module_new(call->engine, call->module_bytes,
        (size_t)original.st_size, &call->module);
    if (call->error != NULL || call->module == NULL) return 11;
    if (actql_compiler_check_module_abi(call->module) != ACTQL_COMPILER_ABI_MATCH) return 12;
    call->error = wasmtime_module_serialize(call->module, &call->image);
    if (call->error != NULL || call->image.data == NULL || call->image.size == 0 ||
        call->image.size > ACTQL_COMPILER_IMAGE_MAX_BYTES ||
        actql_native_owned_contains_live_span(call->owner, call->image.data,
                                              call->image.size) != ACTQL_OWNED_OK) return 13;
    call->output_fd = open(output_path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (call->output_fd < 0) return 14;
    size_t offset = 0;
    while (offset < call->image.size) {
        size_t remaining = call->image.size - offset;
        size_t quantum = remaining < 65536 ? remaining : 65536;
        ssize_t result = write(call->output_fd, call->image.data + offset, quantum);
        if (result <= 0 || (size_t)result > quantum) return 15;
        offset += (size_t)result;
    }
    *image_bytes = offset;
    return close_descriptor(&call->output_fd, &call->fd_close_pending) == 0 ? 0 : 16;
}

int main(int argc, char **argv) {
    assert(argc == 19 && strlen(argv[1]) == 64);
    unsigned char recipe[32];
    for (size_t i = 0; i < 32; i++) {
        int high = hex((unsigned char)argv[1][2 * i]), low = hex((unsigned char)argv[1][2 * i + 1]);
        assert(high >= 0 && low >= 0);
        recipe[i] = (unsigned char)(16 * high + low);
    }
    int64_t material[15];
    for (size_t i = 0; i < 15; i++) {
        const char *value = argv[i + 2];
        assert(*value >= '0' && *value <= '9');
        char *end = NULL;
        errno = 0;
        intmax_t number = strtoimax(value, &end, 10);
        assert(errno == 0 && end != NULL && *end == '\0' && number >= 0 && number <= INT64_MAX);
        material[i] = (int64_t)number;
    }
    size_t bytes = actql_native_domain_borrow_storage_bytes();
    size_t alignment = actql_native_domain_borrow_storage_alignment();
    /* Existing bounded control-copy quantum, not an arena budget or grant.
     * Exact storage remains original and stable through partial map/close. */
    assert(bytes > 0 && bytes <= 65536 && alignment > 0 &&
           alignment <= _Alignof(max_align_t) && _Alignof(max_align_t) % alignment == 0);
    max_align_t record[(bytes + sizeof(max_align_t) - 1) / sizeof(max_align_t)];
    memset(record, 0, sizeof(record));
    /* The original parent confirms spawn/current and the same child binding
     * before this child maps FD4 or allocates any C-API object. EOF, a signal or
     * another byte is a refusal, never permission to bind ambient storage. */
    unsigned char ready = 0;
    ssize_t received;
    do { received = read(STDIN_FILENO, &ready, 1); }
    while (received < 0 && errno == EINTR);
    assert(received == 1 && ready == 'R');
    assert(actql_native_domain_borrow_open(record, bytes, 4, recipe, material) == 0);
    actql_owned_capacity *original = NULL;
    assert(actql_native_domain_borrow_claim_holding(record, &original) == 0);
    assert(actql_native_domain_borrow_transfer_holding(record, original, (uint64_t)material[0], recipe) == 0);
    assert(actql_native_domain_borrow_enter(record) == 0);
    /* Inspect the selected Runtime's actual dependency resolution. The Runtime
     * must use the same imported provider function as this original domain;
     * matching filenames or independently linked capacity copies do not pass. */
    void *runtime = dlopen("@rpath/_libwasmtime.dylib", RTLD_NOW | RTLD_NOLOAD);
    assert(runtime != NULL);
    void *provider_current = dlsym(runtime, "actql_native_owned_current");
    assert(provider_current != NULL &&
           provider_current == dlsym(RTLD_DEFAULT, "actql_native_owned_current"));
    assert(dlclose(runtime) == 0);
    struct compilation call = { .owner = original, .module_fd = -1, .output_fd = -1 };
    size_t image_bytes = 0;
    int result = compile_original(&call, argv[17], argv[18], &image_bytes);
    int handles = close_compilation(&call);
    int leave = actql_native_domain_borrow_leave(record);
    int close = leave == 0 && handles == 0 ?
        actql_native_domain_borrow_close_holding(record, &original) : ACTQL_OWNED_INVALID;
    bool returned = close == ACTQL_OWNED_OK && original == NULL;
    bool runtime_retained = result == 0 && handles == 0 &&
        close == ACTQL_OWNED_BUSY && original != NULL;
    /* BUSY remains a real allocation-level refusal, not Released. The original
     * parent process Owner must still stop execution/IPC and retire this same
     * child region/descriptor. Exit status or Engine drop is not that ACK. */
    printf("{\"compilation_status\":%d,\"image_bytes\":%zu,\"handles_close\":%d,"
           "\"leave\":%d,\"holding_close\":%d,\"holding_closed\":%s,"
           "\"runtime_retained\":%s,\"config_attempted\":%s,\"engine_attempted\":%s,"
           "\"module_attempted\":%s,\"instance\":false,\"physical_acceptance\":false}\n",
           result, image_bytes, handles, leave, close, returned ? "true" : "false",
           runtime_retained ? "true" : "false", call.config_attempted ? "true" : "false",
           call.engine_attempted ? "true" : "false", call.module_attempted ? "true" : "false");
    return result == 0 && handles == 0 && leave == 0 && (returned || runtime_retained) ? 0 : 1;
}
