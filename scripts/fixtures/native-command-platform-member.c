#include "moonbit.h"
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "../../src/platform_native/host_bootstrap/command_platform.h"

/* Controlled member callbacks for the entry record protocol only. They are
 * not the installed filesystem bridge, a complete envelope or load capacity. */
struct actql_native_observed_component_member {
  int kind;
  bool current;
  const void *runtime;
  int *finalized;
};
static int member_current_calls;
static const int original_runtime, foreign_runtime;
static void finalize_member(void *raw) {
  actql_native_observed_component_member *member = raw;
  ++*member->finalized;
}
actql_native_observed_component_member *fixture_member(int kind,
    int foreign, int *finalized) {
  actql_native_observed_component_member *member = moonbit_make_external_object(
    finalize_member, sizeof(*member));
  *member = (actql_native_observed_component_member){
    kind, true, foreign ? &foreign_runtime : &original_runtime, finalized};
  return member;
}
void fixture_member_stop(actql_native_observed_component_member *member) {
  member->current = false;
}
int fixture_member_checks(void) { return member_current_calls; }
int actql_native_observed_component_member_current(
    actql_native_observed_component_member *member) {
  ++member_current_calls;
  return member->current;
}
enum actql_native_command_component_kind
actql_native_observed_component_member_kind(
    actql_native_observed_component_member *member) {
  return member->kind;
}
const void *actql_native_observed_component_member_runtime(
    actql_native_observed_component_member *member) {
  return member->runtime;
}
const char *actql_native_observed_component_member_path(
    actql_native_observed_component_member *member) {
  (void)member; return "/controlled/member.dylib";
}
const char *actql_native_observed_component_member_source(
    actql_native_observed_component_member *member) {
  (void)member; return "1234567890abcdef1234567890abcdef12345678";
}
const char *actql_native_observed_component_member_sha256(
    actql_native_observed_component_member *member) {
  (void)member;
  return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
}
const char *actql_native_observed_component_member_manifest_sha256(
    actql_native_observed_component_member *member) {
  (void)member;
  return "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
}
