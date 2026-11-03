#ifndef ACTQL_RESIDENT_INITIAL_CONTROL_CAPTURE_H
#define ACTQL_RESIDENT_INITIAL_CONTROL_CAPTURE_H
#if defined(__linux__) && defined(__x86_64__) && defined(ACTQL_NATIVE_LINUX_X64_RESIDENT_ENTRY)
/* The selected Linux capture recipe, retained in this command's own image. */
#include "../native_runtime_bundle/initial_control_capture_linux_x64.h"
#else
/* Command-private original capture. Allocation-free OS observation precedes
 * the generic bootstrap and every managed argument/parser/Store operation. */
#include "../../platform_native/host_bootstrap/command_input.h"
#include "../../platform_native/host_bootstrap/initial_loader_environment.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <crt_externs.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <sys/stat.h>
#endif
#ifdef ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
#include ACTQL_RESIDENT_INITIAL_CONTROL_HEADER
#endif

typedef struct {
    bool attempted;
    bool available;
    bool retired;
    int argc;
    const char *const *argv;
    size_t storage_bytes;
    unsigned char arguments[ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES];
    actql_native_loader_environment loader;
#if defined(__APPLE__)
    pid_t process;
    pthread_t thread;
    const struct mach_header_64 *image;
    char executable[PROC_PIDPATHINFO_MAXSIZE];
    struct stat executable_stat;
#endif
} resident_entry;

/* One process-lived initial-control original. No reset or replacement path. */
static resident_entry original_entry;

static bool selected_recipe(void) {
#if defined(__APPLE__) && defined(__aarch64__) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
    const char *source = ACTQL_RESIDENT_SOURCE_SHA;
    const char *recipe = ACTQL_RESIDENT_RECIPE_SHA;
    if (sizeof(ACTQL_RESIDENT_SOURCE_SHA) != 41 ||
        sizeof(ACTQL_RESIDENT_RECIPE_SHA) != 65) return false;
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
#if defined(__APPLE__)
    entry->process = getpid();
    entry->thread = pthread_self();
#endif
#if defined(__APPLE__) && defined(__aarch64__) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
    if (!selected_recipe() || !pthread_main_np() ||
        !actql_native_loader_environment_capture(&entry->loader)) return false;
    int *argc = _NSGetArgc();
    char ***argv = _NSGetArgv();
    char ***environment = _NSGetEnviron();
    if (!argc || !argv || !*argv || !environment || !*environment) return false;
    int captured_argc = *argc;
    const char *const *captured_argv = (const char *const *)*argv;
    actql_bootstrap_command_input_observation input;
    if (actql_bootstrap_measure_command_input(captured_argc,
            captured_argv, ACTQL_RESIDENT_ARGUMENTS,
            ACTQL_RESIDENT_ARGUMENT_BYTES, ACTQL_RESIDENT_ARGUMENT_STORAGE,
            &input) != ACTQL_COMMAND_INPUT_OK) return false;
    size_t environment_bytes = 0, index = 0;
    for (; index < ACTQL_RESIDENT_ENVIRONMENT_ENTRIES; ++index) {
        const char *text = (*environment)[index];
        if (!text) break;
        for (size_t j = 0;; ++j) {
            if (environment_bytes >= ACTQL_RESIDENT_ENVIRONMENT_STORAGE) return false;
            ++environment_bytes;
            if (!text[j]) break;
        }
    }
    if (index == ACTQL_RESIDENT_ENVIRONMENT_ENTRIES) return false;
    entry->image = _NSGetMachExecuteHeader();
    if (!entry->image || proc_pidpath(entry->process, entry->executable,
            sizeof(entry->executable)) <= 0 ||
        stat(entry->executable, &entry->executable_stat) != 0 ||
        !S_ISREG(entry->executable_stat.st_mode)) return false;
    if (*argc != captured_argc || (const char *const *)*argv != captured_argv) return false;
    entry->argc = captured_argc;
    entry->argv = captured_argv;
    entry->storage_bytes = input.storage_bytes;
    size_t cursor = 0;
    for (int i = 0; i < entry->argc; ++i) {
        for (size_t j = 0;; ++j) {
            /* Recheck before each read/write: an input changed after the
             * observation cannot grow the fixed original capture. */
            if (cursor >= input.storage_bytes || cursor >= sizeof(entry->arguments)) return false;
            unsigned char byte = (unsigned char)entry->argv[i][j];
            entry->arguments[cursor++] = byte;
            if (!byte) break;
        }
    }
    entry->available = cursor == input.storage_bytes;
    return entry->available;
#else
    (void)entry;
    return false;
#endif
}

static bool entry_current(resident_entry *entry) {
    if (entry != &original_entry || !entry->available || entry->retired) return false;
#if defined(__APPLE__) && defined(__aarch64__) && defined(ACTQL_RESIDENT_INITIAL_CONTROL_HEADER)
    struct stat current;
    if (entry->process != getpid() || !pthread_main_np() ||
        !pthread_equal(entry->thread, pthread_self()) ||
        entry->image != _NSGetMachExecuteHeader() ||
        !actql_native_loader_environment_current(&entry->loader) ||
        stat(entry->executable, &current) != 0 ||
        current.st_dev != entry->executable_stat.st_dev ||
        current.st_ino != entry->executable_stat.st_ino ||
        current.st_size != entry->executable_stat.st_size ||
        current.st_mtimespec.tv_sec != entry->executable_stat.st_mtimespec.tv_sec ||
        current.st_mtimespec.tv_nsec != entry->executable_stat.st_mtimespec.tv_nsec ||
        *_NSGetArgc() != entry->argc ||
        (const char *const *)*_NSGetArgv() != entry->argv) return false;
    size_t cursor = 0;
    for (int i = 0; i < entry->argc; ++i) {
        for (size_t j = 0;; ++j) {
            if (cursor >= entry->storage_bytes ||
                entry->arguments[cursor] != (unsigned char)entry->argv[i][j]) return false;
            if (!entry->arguments[cursor++]) break;
        }
    }
    return cursor == entry->storage_bytes;
#else
    return false;
#endif
}

#endif
#endif
