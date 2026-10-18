#ifndef ACTQL_NATIVE_COMMAND_PLATFORM_ENTRY_H
#define ACTQL_NATIVE_COMMAND_PLATFORM_ENTRY_H

/* The selected executable retains this entry and its spent load records for
 * the original process lifetime. No component, member getter or caller DATA
 * can construct or replenish an entry. */
#define ACTQL_NATIVE_COMMAND_OPTIONAL_MEMBER_BRIDGE
#include "../../platform_native/host_bootstrap/command_platform.h"
#undef ACTQL_NATIVE_COMMAND_OPTIONAL_MEMBER_BRIDGE
#include <stdatomic.h>
#include <pthread.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

/* A CLI diagnostic may not contain the selected filesystem bridge. Absence is
 * a refusal before dlopen, never a path-only or stock-library fallback. */
struct actql_native_command_platform_load {
  actql_native_command_platform_original *entry;
  actql_native_observed_component_member *member;
  void *module;
  bool attempted, observed, released;
};

struct actql_native_command_platform_original {
  pid_t process;
  pthread_t thread;
  const void *image;
  const char *source;
  const void *runtime;
  char manifest[65];
  /* Entry capture is provenance only. This remains false until the trusted
   * entry connects its complete source/backend-specific initial envelope.
   * There is intentionally no exported setter or caller-selected constructor. */
  bool initial_envelope_admitted;
  bool closing;
  actql_native_command_platform_load loads[2];
};

static _Atomic int actql_command_entry_state;
static actql_native_command_platform_original actql_command_entry;

/* Allocation-free capture from the actual Native main, after original raw
 * input bounds and before managed Command construction. This neither admits
 * the incomplete envelope nor acquires a Host, Root, Library, Read or key. */
void actql_native_client_capture_command_entry(void) {
  int expected = 0;
  if (!atomic_compare_exchange_strong_explicit(&actql_command_entry_state,
      &expected, 1, memory_order_acq_rel, memory_order_acquire)) return;
#if defined(__APPLE__)
  const char *source = actql_native_client_selected_source();
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK || !source) {
    atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
    return;
  }
  actql_command_entry.process = getpid();
  actql_command_entry.thread = pthread_self();
  /* The linker's actual executable symbol needs no loader query, image census
   * or allocation before the selected initial envelope is admitted. Its value
   * is correspondence only, never mapped-image capacity. */
  extern const struct mach_header_64 _mh_execute_header;
  actql_command_entry.image = &_mh_execute_header;
  actql_command_entry.source = source;
  atomic_store_explicit(&actql_command_entry_state, 2, memory_order_release);
#else
  atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
#endif
}

static bool actql_command_entry_thread(
    const actql_native_command_platform_original *entry) {
  return entry == &actql_command_entry &&
    atomic_load_explicit(&actql_command_entry_state, memory_order_acquire) == 2 &&
    entry->process == getpid() && pthread_equal(entry->thread, pthread_self());
}

actql_native_command_platform_original *
actql_native_command_platform_current(void) {
  actql_native_command_platform_original *entry = &actql_command_entry;
  return actql_command_entry_thread(entry) &&
    entry->initial_envelope_admitted && !entry->closing ? entry : NULL;
}

static bool actql_command_member_bridge(void) {
  return actql_native_observed_component_member_current &&
    actql_native_observed_component_member_kind &&
    actql_native_observed_component_member_runtime &&
    actql_native_observed_component_member_path &&
    actql_native_observed_component_member_source &&
    actql_native_observed_component_member_sha256 &&
    actql_native_observed_component_member_manifest_sha256;
}

static bool actql_command_hex(const char *text, size_t length) {
  if (!text) return false;
  for (size_t i = 0; i < length; ++i)
    if (!((text[i] >= '0' && text[i] <= '9') ||
          (text[i] >= 'a' && text[i] <= 'f'))) return false;
  return text[length] == 0;
}

actql_native_command_platform_load *actql_native_command_platform_begin_load(
    actql_native_command_platform_original *entry,
    enum actql_native_command_component_kind kind,
    actql_native_observed_component_member *member) {
  if (!entry || entry != actql_native_command_platform_current() || !member ||
      kind < ACTQL_NATIVE_COMMAND_SQLITE_COMPONENT ||
      kind > ACTQL_NATIVE_COMMAND_CRYPTO_COMPONENT ||
      !actql_command_member_bridge()) return NULL;
  actql_native_command_platform_load *load = &entry->loads[kind - 1];
  if (load->attempted ||
      actql_native_observed_component_member_kind(member) != kind ||
      !actql_native_observed_component_member_current(member)) return NULL;
  const void *runtime = actql_native_observed_component_member_runtime(member);
  const char *source = actql_native_observed_component_member_source(member);
  const char *hash = actql_native_observed_component_member_sha256(member);
  const char *manifest =
    actql_native_observed_component_member_manifest_sha256(member);
  const char *path = actql_native_observed_component_member_path(member);
  if (!runtime || !actql_command_hex(source, 40) ||
      strcmp(source, entry->source) != 0 || !actql_command_hex(hash, 64) ||
      !actql_command_hex(manifest, 64) || !path || path[0] != '/' ||
      strnlen(path, 4097) > 4096 ||
      (entry->runtime && (entry->runtime != runtime ||
                         strcmp(entry->manifest, manifest) != 0))) return NULL;
  if (!entry->runtime) {
    entry->runtime = runtime;
    memcpy(entry->manifest, manifest, sizeof(entry->manifest));
  }
  moonbit_incref(member);
  load->entry = entry;
  load->member = member;
  load->attempted = true;
  return load;
}

static bool actql_command_original_load(actql_native_command_platform_load *load) {
  /* Compare addresses before dereferencing a caller-provided pointer. */
  return (load == &actql_command_entry.loads[0] ||
          load == &actql_command_entry.loads[1]) &&
    actql_command_entry_thread(&actql_command_entry) &&
    load->entry == &actql_command_entry && load->attempted;
}

int actql_native_command_platform_load_current(
    actql_native_command_platform_load *load) {
  return actql_command_original_load(load) && !load->released && load->member &&
    actql_native_command_platform_current() == load->entry &&
    actql_native_observed_component_member_current(load->member);
}

int actql_native_command_platform_observe_load(
    actql_native_command_platform_load *load, void *module) {
  if (!actql_command_original_load(load) || load->observed || load->released)
    return 0;
  /* Record the SAME partial handle even when member currentness changed during
   * dlopen. Normal validation may refuse; original cleanup still owns it. */
  load->module = module;
  load->observed = true;
  return actql_native_command_platform_load_current(load);
}

int actql_native_command_platform_module_released(
    actql_native_command_platform_load *load, void *module) {
  if (!actql_command_original_load(load) || !load->observed ||
      load->module != module) return 0;
  if (load->released) return 1;
  actql_native_observed_component_member *member = load->member;
  load->member = NULL;
  load->released = true;
  moonbit_decref(member);
  /* Leave both attempted and the Runtime association spent. Never inspect the
   * borrowed Runtime or freed member after this acknowledgment. */
  return 1;
}

#endif
