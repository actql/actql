#include <stddef.h>
#include "../../src/platform_native/host_bootstrap/command_platform.h"

/* The standalone preargument diagnostic has no filesystem/Runtime owner.
 * These test-only callbacks supply no member and cannot admit a load. The
 * selected executable links the actual filesystem implementation instead. */
int actql_native_observed_component_member_current(
    actql_native_observed_component_member *member) {
  (void)member; return 0;
}
enum actql_native_command_component_kind
actql_native_observed_component_member_kind(
    actql_native_observed_component_member *member) {
  (void)member; return 0;
}
const void *actql_native_observed_component_member_runtime(
    actql_native_observed_component_member *member) {
  (void)member; return NULL;
}
const char *actql_native_observed_component_member_path(
    actql_native_observed_component_member *member) {
  (void)member; return NULL;
}
const char *actql_native_observed_component_member_source(
    actql_native_observed_component_member *member) {
  (void)member; return NULL;
}
const char *actql_native_observed_component_member_sha256(
    actql_native_observed_component_member *member) {
  (void)member; return NULL;
}
const char *actql_native_observed_component_member_manifest_sha256(
    actql_native_observed_component_member *member) {
  (void)member; return NULL;
}
