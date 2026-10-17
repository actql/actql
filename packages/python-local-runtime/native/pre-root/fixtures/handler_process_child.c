/* Disposable child for the actual Native scoped-process conformance. Link
 * against the selected single provider; never include another provider body.
 * The parent retains the original Host/loan/holder before starting this file. */
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../owned_region.h"

void actql_test_original_extent_observation(actql_owned_capacity *, int);

static size_t size_argument(const char *value) {
    assert(value != NULL && value[0] >= '0' && value[0] <= '9');
    char *end = NULL;
    errno = 0;
    unsigned long long selected = strtoull(value, &end, 10);
    assert(errno == 0 && end != NULL && *end == '\0' && selected <= SIZE_MAX);
    return (size_t)selected;
}

int main(int argc, char **argv) {
    assert(argc == 8);
    const bool retained_panic = strcmp(argv[7], "retained-panic") == 0;
    const bool deliberate_abort = strcmp(argv[7], "retained-panic-abort") == 0;
    assert(retained_panic || deliberate_abort || strcmp(argv[7], "all-original") == 0);
    int descriptor = open(argv[1], O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    assert(descriptor >= 0);
    long selected_page = sysconf(_SC_PAGESIZE); assert(selected_page > 0);
    size_t page = (size_t)selected_page;
    struct stat file;
    assert(fstat(descriptor, &file) == 0 && S_ISREG(file.st_mode) &&
           (file.st_mode & 0777) == 0600 && file.st_uid == geteuid() &&
           file.st_size >= 0 && (uint64_t)file.st_size == 64 * page);
    actql_owned_extent_reference reference = {
        .device = (uint64_t)file.st_dev, .inode = (uint64_t)file.st_ino,
        .generation = 1, .capacity = 64 * page,
        .offset = size_argument(argv[3]), .length = size_argument(argv[4]),
        .writable = true
    };
    memset(reference.recipe, 17, sizeof(reference.recipe));
    actql_owned_extent_view view = {0};
    actql_owned_capacity *original = NULL;
    assert(actql_native_owned_map_extent_payload(descriptor, &reference,
               size_argument(argv[5]), size_argument(argv[6]), &view) == 0 &&
           actql_native_owned_borrow_extent_domain(&view, &original) == 0);
    /* Before this original channel command, the Native parent can observe
     * that the original holder is live. EOF is not a successful handler run. */
    char command = 0;
    if (read(STDIN_FILENO, &command, 1) != 1 || command != 'R') return 2;
    assert(actql_native_owned_enter(original) == 0);
    void *library = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
    if (library == NULL) { fprintf(stderr, "%s\n", dlerror()); return 3; }
    void *symbol = dlsym(library, "actql_test_original_thread_case");
    int (*run)(int) = NULL;
    assert(sizeof(run) == sizeof(symbol)); memcpy(&run, &symbol, sizeof(run)); assert(run != NULL);
    symbol = dlsym(library, "actql_test_original_provider_current_address");
    void *(*address)(void) = NULL;
    assert(sizeof(address) == sizeof(symbol)); memcpy(&address, &symbol, sizeof(address));
    assert(address != NULL && address() == dlsym(RTLD_DEFAULT, "actql_native_owned_current"));
    /* Both selected domain cases retain the actual std mutex. The older full
     * sequence also has a root-only try_close counter; applying that counter
     * to an interior domain is not a domain-completion or exhaustion proof. */
    const int selected_cases = retained_panic || deliberate_abort ? 2 : 4;
    for (int index = 0; index < selected_cases; index++) {
        assert(run(index) == 0);
        actql_test_original_extent_observation(original, index + 1);
    }
    assert(actql_native_owned_leave(original) == 0);
    actql_owned_capacity *same = original;
    assert(actql_native_owned_return_extent_domain_borrow(&view, &original) == ACTQL_OWNED_BUSY &&
           original == same && view.domain_live &&
           actql_native_owned_close_extent_view(&view) == ACTQL_OWNED_BUSY);
    /* All handler joins completed, but the real std backtrace allocation is
     * still process-retained. This is not a holding-close success. The Native
     * parent must confirm process/IPC stop and actually clean its original
     * exclusive view and descriptor before reporting region retirement. */
    printf("{\"handler_cases\":%d,\"RuntimeRetained\":true,"
         "\"borrow_return\":\"refused\",\"holding_closed\":false}\n", selected_cases);
    assert(fflush(stdout) == 0);
    if (deliberate_abort) {
        fputs("deliberate retained-process fixture abort; handler success not claimed\n", stderr);
        raise(SIGABRT);
        return 4;
    }
    assert(close(descriptor) == 0);
    return 0;
}
