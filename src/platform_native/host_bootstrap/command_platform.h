#ifndef ACTQL_NATIVE_COMMAND_PLATFORM_H
#define ACTQL_NATIVE_COMMAND_PLATFORM_H

/* Private connection between the selected Native entry and the existing
 * filesystem/component owners. There is deliberately no constructor accepting
 * a path, identity, quote or limit. The entry retains the actual initial
 * operational original; the filesystem owner retains the observed member.
 * Neither opaque type can be reconstructed from public DATA. */
typedef struct actql_native_command_platform_original
  actql_native_command_platform_original;
typedef struct actql_native_command_platform_load
  actql_native_command_platform_load;
typedef struct actql_native_observed_component_member
  actql_native_observed_component_member;

enum actql_native_command_component_kind {
  ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT = 1,
  ACTQL_NATIVE_COMMAND_CRYPTO_COMPONENT = 2
};

/* Filesystem-owner projections of its SAME retained Runtime/member. These
 * getters do not create an original or permission. Text is borrowed, bounded
 * and NUL-terminated by that owner (path 4096, source 40, hashes 64). Runtime
 * association is nominal, retained by the caller; it is never a serialized
 * identity. current includes the original Root/stat/namespace/Read checks. */
int actql_native_observed_component_member_current(
  actql_native_observed_component_member *member);
enum actql_native_command_component_kind
actql_native_observed_component_member_kind(
  actql_native_observed_component_member *member);
const void *actql_native_observed_component_member_runtime(
  actql_native_observed_component_member *member);
const char *actql_native_observed_component_member_path(
  actql_native_observed_component_member *member);
const char *actql_native_observed_component_member_source(
  actql_native_observed_component_member *member);
const char *actql_native_observed_component_member_sha256(
  actql_native_observed_component_member *member);
const char *actql_native_observed_component_member_manifest_sha256(
  actql_native_observed_component_member *member);


/* Borrow the selected entry's existing original. Missing selection, incomplete
 * envelope, retirement, fork inheritance or a foreign thread returns NULL.
 * Looking up the original never creates, renews or replenishes it. */
actql_native_command_platform_original *
actql_native_command_platform_current(void);

/* Private pre-acquisition observation only. The actual original stays with
 * this Owner and is required again by every load; this is not a constructor,
 * transferable capacity or a substitute for the complete selected envelope. */
int actql_native_command_platform_available(void);

/* Before dlopen, including all module initializers. The same Runtime has
 * already observed and hashed this member through its retained Root/Reader.
 * The implementation checks that actual member again through its filesystem
 * owner, together with the entry/installation/generation/recipe association.
 * Refusal creates no load permission. A consumed attempt cannot be replaced;
 * shared process/thread coverage is never refilled by a child phase or close.
 * The accepted load retains this member until its own module acknowledgment;
 * the component receiver and enclosing command retain their original Runtime. */
actql_native_command_platform_load *actql_native_command_platform_begin_load(
  actql_native_command_platform_original *original,
  enum actql_native_command_component_kind kind,
  actql_native_observed_component_member *member);

/* Record this exact dlopen result before symbol binding or initialization.
 * The same component receiver retains the handle even if origin validation
 * fails. NULL records a failed attempt, rather than allowing another load.
 * This observation is not validation of the component's symbols or API. */
int actql_native_command_platform_observe_load(
  actql_native_command_platform_load *load, void *module);

/* Same original process/thread/member checks before initialization and use.
 * Component owners additionally validate every fixed symbol's actual image
 * origin before invoking it. Failure of this NORMAL current check does not
 * discard or prevent cleanup of the same partial receiver. Cleanup retains
 * the original thread, handle and existing component/Read obligations. */
int actql_native_command_platform_load_current(
  actql_native_command_platform_load *load);

/* Only after the same component owner receives its actual module-reference
 * release ACK. A failed/unconfirmed dlclose is not passed here as success.
 * NULL is accepted only for a previously observed failed load that acquired no
 * module; it cannot stand in for a lost module acknowledgment. This drops the
 * load's retained member alias, after which it must never dereference that
 * member or its borrowed Runtime. Only process-lived accounting and the spent
 * attempt remain. This does not acknowledge component/TLS shutdown, complete
 * image retirement, Read/context/backing cleanup or return initial coverage. */
int actql_native_command_platform_module_released(
  actql_native_command_platform_load *load, void *module);

#endif
