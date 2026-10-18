#ifndef ACTQL_BOOTSTRAP_COMMAND_INPUT_H
#define ACTQL_BOOTSTRAP_COMMAND_INPUT_H

#include <stddef.h>
#include <stdint.h>

/* Private, allocation-free observation before the selected command copies OS
 * arguments. Bounds come from the original installer's complete profile; this
 * DATA neither acquires backing nor admits a Host, Read, command or authority.
 * Include argv[0], which the pinned runtime copies before argparse drops it.
 * Per-argument bytes exclude NUL; total storage includes every terminal NUL.
 * No flag interpretation, text conversion, trimming or identifier rewriting. */
typedef struct {
    size_t arguments;
    size_t storage_bytes;
    size_t longest_argument_bytes;
} actql_bootstrap_command_input_observation;

enum {
    ACTQL_COMMAND_INPUT_OK = 0,
    ACTQL_COMMAND_INPUT_INVALID = 1,
    ACTQL_COMMAND_INPUT_ARGUMENTS = 2,
    ACTQL_COMMAND_INPUT_ARGUMENT_BYTES = 3,
    ACTQL_COMMAND_INPUT_TOTAL_BYTES = 4,
    ACTQL_COMMAND_INPUT_NOT_SELECTED = 5,
    ACTQL_COMMAND_INPUT_SOURCE = 6,
    ACTQL_COMMAND_INPUT_CONTEXT = 7,
    ACTQL_COMMAND_INPUT_SCRATCH = 8
};

/* Match the existing selected native path bound. Keep one immutable original
 * text copy in initial control before any Read/inspection allocation. This is
 * input DATA only, not a directory observation, resource or authorization. */
#define ACTQL_COMMAND_SCRATCH_BYTES 4096
static int actql_bootstrap_capture_command_scratch(
    const char *original, char out[ACTQL_COMMAND_SCRATCH_BYTES + 1]) {
    if (original == NULL || original[0] == '\0') original = "/tmp";
    size_t length = 0;
    while (length <= ACTQL_COMMAND_SCRATCH_BYTES && original[length] != '\0')
        ++length;
    if (length > ACTQL_COMMAND_SCRATCH_BYTES)
        return ACTQL_COMMAND_INPUT_SCRATCH;
    for (size_t index = 0; index <= length; ++index) out[index] = original[index];
    return ACTQL_COMMAND_INPUT_OK;
}

static int actql_bootstrap_measure_command_input(
    int argc, const char *const *argv,
    size_t maximum_arguments, size_t maximum_argument_bytes,
    size_t maximum_storage_bytes,
    actql_bootstrap_command_input_observation *out) {
    if (out == NULL) return ACTQL_COMMAND_INPUT_INVALID;
    *out = (actql_bootstrap_command_input_observation){0};
    if (argc <= 0 || argv == NULL || maximum_arguments == 0 ||
        maximum_storage_bytes == 0)
        return ACTQL_COMMAND_INPUT_INVALID;
    if ((uintmax_t)argc > (uintmax_t)maximum_arguments)
        return ACTQL_COMMAND_INPUT_ARGUMENTS;
    actql_bootstrap_command_input_observation value = {0};
    for (int index = 0; index < argc; ++index) {
        if (argv[index] == NULL) return ACTQL_COMMAND_INPUT_INVALID;
        size_t bytes = 0;
        for (;;) {
            /* Check remaining total storage before the next read as well as
             * before addition; SIZE_MAX limits cannot wrap the scan counter. */
            if (value.storage_bytes >= maximum_storage_bytes ||
                bytes >= maximum_storage_bytes - value.storage_bytes)
                return ACTQL_COMMAND_INPUT_TOTAL_BYTES;
            if (argv[index][bytes] == '\0') break;
            if (bytes >= maximum_argument_bytes)
                return ACTQL_COMMAND_INPUT_ARGUMENT_BYTES;
            ++bytes;
        }
        value.storage_bytes += bytes + 1;
        if (bytes > value.longest_argument_bytes)
            value.longest_argument_bytes = bytes;
        ++value.arguments;
    }
    *out = value;
    return ACTQL_COMMAND_INPUT_OK;
}

typedef struct {
    actql_bootstrap_command_input_observation input;
    size_t context_bytes;
} actql_bootstrap_command_preparation_observation;

/* The existing launcher marker selects this preparation path, not a second
 * parser of --mode or command words. The selected compiler supplies source;
 * neither a marker nor a matching spelling supplies backing or permission.
 * The original caller must retain the actual inputs and bind its same Host;
 * this observation cannot be adopted as an acquisition/cleanup receipt. */
static int actql_bootstrap_measure_command_preparation(
    const char *selected_source, const char *runtime_context,
    int argc, const char *const *argv,
    size_t maximum_arguments, size_t maximum_argument_bytes,
    size_t maximum_storage_bytes, size_t maximum_context_bytes,
    actql_bootstrap_command_preparation_observation *out) {
    if (out == NULL) return ACTQL_COMMAND_INPUT_INVALID;
    *out = (actql_bootstrap_command_preparation_observation){0};
    if (runtime_context == NULL) return ACTQL_COMMAND_INPUT_NOT_SELECTED;
    if (selected_source == NULL) return ACTQL_COMMAND_INPUT_SOURCE;
    for (size_t index = 0; index < 40; ++index) {
        unsigned char byte = (unsigned char)selected_source[index];
        if (!((byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f')))
            return ACTQL_COMMAND_INPUT_SOURCE;
    }
    if (selected_source[40] != '\0') return ACTQL_COMMAND_INPUT_SOURCE;
    size_t context_bytes = 0;
    while (runtime_context[context_bytes] != '\0') {
        if (context_bytes >= maximum_context_bytes || context_bytes == SIZE_MAX)
            return ACTQL_COMMAND_INPUT_CONTEXT;
        ++context_bytes;
    }
    if (context_bytes == 0) return ACTQL_COMMAND_INPUT_CONTEXT;
    actql_bootstrap_command_preparation_observation value = {0};
    int status = actql_bootstrap_measure_command_input(argc, argv,
        maximum_arguments, maximum_argument_bytes, maximum_storage_bytes,
        &value.input);
    if (status != ACTQL_COMMAND_INPUT_OK) return status;
    value.context_bytes = context_bytes;
    *out = value;
    return ACTQL_COMMAND_INPUT_OK;
}

#endif
