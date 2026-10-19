#include "../../src/platform_native/host_bootstrap/command_input.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    assert(argc == 2);
    actql_bootstrap_command_input_observation observed = {99, 99, 99};
    const char *values[] = {"actql", "", "\xc3\xa9", "--mode=local"};
    if (strcmp(argv[1], "exact-storage") == 0) {
        assert(actql_bootstrap_measure_command_input(4, values, 4, 12, 23,
            &observed) == ACTQL_COMMAND_INPUT_OK);
        assert(observed.arguments == 4 && observed.storage_bytes == 23 &&
            observed.longest_argument_bytes == 12);
    } else if (strcmp(argv[1], "no-partial-observation") == 0) {
        assert(actql_bootstrap_measure_command_input(4, values, 4, 12, 22,
            &observed) == ACTQL_COMMAND_INPUT_TOTAL_BYTES);
        assert(observed.arguments == 0 && observed.storage_bytes == 0 &&
            observed.longest_argument_bytes == 0);
    } else if (strcmp(argv[1], "argument-limit") == 0) {
        assert(actql_bootstrap_measure_command_input(4, values, 3, 12, 23,
            &observed) == ACTQL_COMMAND_INPUT_ARGUMENTS);
        assert(actql_bootstrap_measure_command_input(4, values, 4, 11, 23,
            &observed) == ACTQL_COMMAND_INPUT_ARGUMENT_BYTES);
        const char *empty[] = {""};
        assert(actql_bootstrap_measure_command_input(1, empty, 1, 0, 1,
            &observed) == ACTQL_COMMAND_INPUT_OK);
        assert(observed.arguments == 1 && observed.storage_bytes == 1);
    } else if (strcmp(argv[1], "raw-bytes-and-original-argv") == 0) {
        const char unusual[] = "\xff\xfe";
        const char *raw[] = {"p", unusual, "--mode=remote"};
        assert(actql_bootstrap_measure_command_input(3, raw, SIZE_MAX,
            SIZE_MAX, SIZE_MAX, &observed) == ACTQL_COMMAND_INPUT_OK);
        assert(observed.arguments == 3 && observed.storage_bytes == 19);
        assert(raw[1] == unusual && (unsigned char)raw[1][0] == 255);
        /* Text conversion remains with the existing OS-string owner. The
         * observer neither reinterprets invalid UTF-8 nor chooses the route. */
    } else if (strcmp(argv[1], "invalid-input") == 0) {
        assert(actql_bootstrap_measure_command_input(-1, values, 4, 12, 23,
            &observed) == ACTQL_COMMAND_INPUT_INVALID);
        assert(actql_bootstrap_measure_command_input(1, NULL, 4, 12, 23,
            &observed) == ACTQL_COMMAND_INPUT_INVALID);
        const char *missing[] = {"p", NULL};
        assert(actql_bootstrap_measure_command_input(2, missing, 4, 12, 23,
            &observed) == ACTQL_COMMAND_INPUT_INVALID);
        assert(observed.arguments == 0 && observed.storage_bytes == 0);
    } else if (strcmp(argv[1], "selected-preparation") == 0) {
        actql_bootstrap_command_preparation_observation selected;
        assert(actql_bootstrap_measure_command_preparation(
            "0123456789abcdef0123456789abcdef01234567", "{}",
            4, values, 4, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_OK);
        assert(selected.context_bytes == 2 && selected.input.arguments == 4 &&
            selected.input.storage_bytes == 23);
    } else if (strcmp(argv[1], "unselected-and-malformed-source") == 0) {
        actql_bootstrap_command_preparation_observation selected;
        assert(actql_bootstrap_measure_command_preparation(NULL, NULL,
            0, NULL, 0, 0, 0, 0, &selected) == ACTQL_COMMAND_INPUT_NOT_SELECTED);
        assert(actql_bootstrap_measure_command_preparation(NULL, "{}",
            4, values, 4, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_SOURCE);
        assert(actql_bootstrap_measure_command_preparation(
            "0123456789ABCDEF0123456789abcdef01234567", "{}",
            4, values, 4, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_SOURCE);
        assert(actql_bootstrap_measure_command_preparation("short", "{}",
            4, values, 4, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_SOURCE);
        assert(selected.context_bytes == 0 && selected.input.arguments == 0);
    } else if (strcmp(argv[1], "selected-context-refusal") == 0) {
        actql_bootstrap_command_preparation_observation selected;
        const char source[] = "0123456789abcdef0123456789abcdef01234567";
        assert(actql_bootstrap_measure_command_preparation(source, "{}",
            4, values, 4, 12, 23, 1, &selected) == ACTQL_COMMAND_INPUT_CONTEXT);
        assert(actql_bootstrap_measure_command_preparation(source, "",
            4, values, 4, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_CONTEXT);
        assert(actql_bootstrap_measure_command_preparation(source, "{}",
            4, values, 3, 12, 23, 2, &selected) == ACTQL_COMMAND_INPUT_ARGUMENTS);
        assert(selected.context_bytes == 0 && selected.input.arguments == 0);
    } else {
        return 2;
    }
    printf("{\"case\":\"%s\",\"passed\":true}\n", argv[1]);
    return 0;
}
