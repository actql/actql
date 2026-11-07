#ifndef ACTQL_BUNDLE_INITIAL_CONTROL_CAPTURE_LINUX_X64_H
#define ACTQL_BUNDLE_INITIAL_CONTROL_CAPTURE_LINUX_X64_H
#if !defined(__linux__) || !defined(__x86_64__) || \
    !defined(ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY)
#error "The bundle capture requires its selected Linux x64 glibc entry"
#endif
#include <features.h>
#if !defined(__GLIBC__)
#error "The selected Linux bundle entry requires glibc"
#endif
/* This private entry supplies the same opaque capture operations as the
 * existing Darwin entry. It cannot select the unscoped/default process port. */
#define ACTQL_RESIDENT_INITIAL_CONTROL_CAPTURE_H
#include "../../platform_native/host_bootstrap/command_input.h"
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#ifdef ACTQL_BUNDLE_INITIAL_CONTROL_HEADER
#include ACTQL_BUNDLE_INITIAL_CONTROL_HEADER
#elif defined(ACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
#include ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
#endif

/* glibc's executable init-array call supplies the original main arguments.
 * Retain only those process-lived pointers here; no allocation or argv copy. */
static struct { bool seen; int argc; char **argv; } bundle_linux_startup;
__attribute__((constructor(101)))
static void bundle_linux_capture_startup(int argc, char **argv, char **environment) {
    (void)environment;
    if (bundle_linux_startup.seen) return;
    bundle_linux_startup.seen = true;
    bundle_linux_startup.argc = argc;
    bundle_linux_startup.argv = argv;
}

typedef struct {
    bool attempted, available, retired, loader_refused;
    int argc;
    const char *const *argv;
    size_t storage_bytes;
    unsigned char arguments[ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES];
    pid_t process;
    pthread_t thread;
    unsigned long image;
    struct stat executable_stat;
} resident_entry;
static resident_entry original_entry;

static bool bundle_linux_loader_supported(void) {
    extern char **environ;
    if (!environ) return false;
    for (size_t i = 0; i < 10000; ++i) {
        const char *text = environ[i];
        if (!text) return true;
        /* Names only, bounded by fixed literals; values are never observed. */
        if (strncmp(text, "LD_", 3) == 0 ||
            strncmp(text, "GLIBC_TUNABLES=", 15) == 0) return false;
    }
    return false;
}
static bool bundle_linux_cleanup_current(resident_entry *entry) {
    return entry == &original_entry && entry->process == getpid() &&
        syscall(SYS_gettid) == getpid() && pthread_equal(entry->thread, pthread_self());
}
static bool selected_recipe(void) {
#if defined(ACTQL_BUNDLE_INITIAL_CONTROL_HEADER) || \
    (defined(ACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER))
    const char *source = ACTQL_RESIDENT_SOURCE_SHA;
    const char *recipe = ACTQL_RESIDENT_RECIPE_SHA;
    if (sizeof(ACTQL_RESIDENT_SOURCE_SHA) != 41 ||
        sizeof(ACTQL_RESIDENT_RECIPE_SHA) != 65 ||
        ACTQL_RESIDENT_TARGET_LINUX_X64 != 1) return false;
    for (size_t i = 0; i < 64; ++i) {
        unsigned char r = (unsigned char)recipe[i];
        if (!((r >= '0' && r <= '9') || (r >= 'a' && r <= 'f'))) return false;
        if (i < 40) {
            unsigned char s = (unsigned char)source[i];
            if (!((s >= '0' && s <= '9') || (s >= 'a' && s <= 'f'))) return false;
        }
    }
    return ACTQL_RESIDENT_ARGUMENT_STORAGE <= sizeof(original_entry.arguments) &&
        ACTQL_RESIDENT_GENERATION > 0 && ACTQL_RESIDENT_CAPACITY > 0 &&
        ACTQL_RESIDENT_CONTROL_ENVELOPE > 0;
#else
    return false;
#endif
}
static bool capture_entry(resident_entry *entry) {
    if (entry->attempted) return false;
    entry->attempted = true;
    entry->process = getpid(); entry->thread = pthread_self();
#if defined(ACTQL_BUNDLE_INITIAL_CONTROL_HEADER) || \
    (defined(ACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER))
    if (!selected_recipe() || syscall(SYS_gettid) != getpid() ||
        !bundle_linux_startup.seen || !bundle_linux_loader_supported()) return false;
    int argc = bundle_linux_startup.argc;
    const char *const *argv = (const char *const *)bundle_linux_startup.argv;
    actql_bootstrap_command_input_observation input;
    if (actql_bootstrap_measure_command_input(argc, argv, ACTQL_RESIDENT_ARGUMENTS,
            ACTQL_RESIDENT_ARGUMENT_BYTES, ACTQL_RESIDENT_ARGUMENT_STORAGE,
            &input) != ACTQL_COMMAND_INPUT_OK) return false;
    extern char **environ;
    size_t bytes = 0, index = 0;
    for (; index < ACTQL_RESIDENT_ENVIRONMENT_ENTRIES; ++index) {
        const char *text = environ[index];
        if (!text) break;
        for (size_t j = 0;; ++j) {
            if (bytes >= ACTQL_RESIDENT_ENVIRONMENT_STORAGE) return false;
            ++bytes; if (!text[j]) break;
        }
    }
    if (index == ACTQL_RESIDENT_ENVIRONMENT_ENTRIES) return false;
    entry->image = getauxval(AT_PHDR);
    if (!entry->image || stat("/proc/self/exe", &entry->executable_stat) != 0 ||
        !S_ISREG(entry->executable_stat.st_mode)) return false;
    entry->argc = argc; entry->argv = argv; entry->storage_bytes = input.storage_bytes;
    size_t cursor = 0;
    for (int i = 0; i < argc; ++i) for (size_t j = 0;; ++j) {
        if (cursor >= input.storage_bytes || cursor >= sizeof(entry->arguments)) return false;
        unsigned char byte = (unsigned char)argv[i][j];
        entry->arguments[cursor++] = byte; if (!byte) break;
    }
    entry->available = cursor == input.storage_bytes;
    return entry->available;
#else
    return false;
#endif
}
static bool entry_current(resident_entry *entry) {
    if (!bundle_linux_cleanup_current(entry) || !entry->available || entry->retired ||
        entry->loader_refused) return false;
    if (!bundle_linux_loader_supported()) { entry->loader_refused = true; return false; }
    struct stat current;
    if (entry->image != getauxval(AT_PHDR) ||
        stat("/proc/self/exe", &current) != 0 ||
        current.st_dev != entry->executable_stat.st_dev ||
        current.st_ino != entry->executable_stat.st_ino ||
        current.st_size != entry->executable_stat.st_size ||
        current.st_mtim.tv_sec != entry->executable_stat.st_mtim.tv_sec ||
        current.st_mtim.tv_nsec != entry->executable_stat.st_mtim.tv_nsec ||
        bundle_linux_startup.argc != entry->argc ||
        (const char *const *)bundle_linux_startup.argv != entry->argv) return false;
    size_t cursor = 0;
    for (int i = 0; i < entry->argc; ++i) for (size_t j = 0;; ++j) {
        if (cursor >= entry->storage_bytes ||
            entry->arguments[cursor] != (unsigned char)entry->argv[i][j]) return false;
        if (!entry->arguments[cursor++]) break;
    }
    return cursor == entry->storage_bytes;
}
#endif
