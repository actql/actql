#ifndef ACTQL_NATIVE_COMMAND_PLATFORM_ENTRY_H
#define ACTQL_NATIVE_COMMAND_PLATFORM_ENTRY_H

/* The selected executable retains this entry and its spent load records for
 * the original process lifetime. No component, member getter or caller DATA
 * can construct or replenish an entry. */
#include "../../platform_native/host_bootstrap/command_platform.h"
#include "command_output.h"
#include "command_initial_parser_volume.h"
#include "command_initial_stack.h"
#include "command_initial_stdio.h"
#include <stdatomic.h>
#include <pthread.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

/* The selected executable links the existing filesystem Owner bridge. A
 * standalone control-only fixture supplies explicit unavailable callbacks;
 * production has no alternate member factory or path-only fallback. */
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
  /* Complete source/backend-specific co-phase selection precedes the first
   * allocator setup. No public input or getter can set this private state. */
  bool initial_coverage_complete;
  size_t initial_managed_selection[4];
  /* Parser allocation volume only; never promotes initial coverage. */
  size_t initial_parser_allocation_volume;
  actql_native_initial_managed_original *initial_managed;
  actql_bootstrap_command_stack initial_stack;
  actql_bootstrap_command_stdio initial_stdio;
  actql_bootstrap_command_output output_control;
  bool closing;
  actql_native_command_platform_load loads[2];
};

static _Atomic int actql_command_entry_state;
static actql_native_command_platform_original actql_command_entry;

#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
static _Noreturn void actql_command_initial_refusal(void) {
  static const char message[] =
    "actql-native-client: LocalCommandInitialCoverageUnavailable\n";
  /* No managed startup or stdio allocation follows a missing/partial initial
   * supplier. This bounded error is not an ACK for any retained original. */
  (void)write(STDERR_FILENO, message, sizeof(message) - 1);
  _exit(1);
}
#endif

bool actql_native_command_platform_managed_selection(
    actql_native_command_platform_original *entry, size_t out[4]) {
  /* Check nominal membership before dereferencing an external pointer. This
   * reader does not depend on managed_current or phase-two platform_current:
   * it is used by the actual original allocator constructor itself. */
  if (!out || entry != &actql_command_entry) return false;
  int state = atomic_load_explicit(&actql_command_entry_state, memory_order_acquire);
  if ((state != 1 && state != 2) || entry->closing ||
      entry->process != getpid() ||
      !pthread_equal(entry->thread, pthread_self()) ||
      entry->source != actql_command_input_source ||
      actql_command_early_input_status != ACTQL_COMMAND_INPUT_OK ||
      !actql_bootstrap_command_stack_current(&entry->initial_stack) ||
      !entry->initial_coverage_complete) return false;
  for (size_t index = 0; index < 4; ++index)
    out[index] = entry->initial_managed_selection[index];
  return true;
}

/* Capture before the generated MoonBit module initializers, not merely before
 * Command construction in MoonBit main. Covered output/allocator setup follows
 * only the complete original initial selection. No Host, Root, Library, Read,
 * key or loader reference is acquired by this entry. */
__attribute__((constructor)) static void actql_command_capture_process_entry(void) {
  int expected = 0;
  if (!atomic_compare_exchange_strong_explicit(&actql_command_entry_state,
      &expected, -2, memory_order_acq_rel, memory_order_acquire)) return;
  /* Capture the same OS-created main-thread stack before bounded input and
   * parser work. Failed capture remains with this one entry; compatibility
   * selection is still decided by its original input below. */
  (void)actql_bootstrap_capture_command_stack(&actql_command_entry.initial_stack);
  actql_native_client_capture_initial_input();
#if defined(__APPLE__)
  const char *source = actql_native_client_selected_source();
  if (!source) {
    atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
    if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED)
      actql_command_initial_refusal();
#endif
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
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED &&
      !actql_bootstrap_command_stack_current(&actql_command_entry.initial_stack)) {
    atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
    actql_command_initial_refusal();
#endif
    return;
  }
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED &&
      !actql_command_initial_parser_volume(
      actql_command_input.input.arguments, actql_command_input.input.storage_bytes,
      actql_command_argument_classes,
      &actql_command_entry.initial_parser_allocation_volume)) {
    atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
    actql_command_initial_refusal();
#endif
    return;
  }
  atomic_store_explicit(&actql_command_entry_state, 1, memory_order_release);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED) {
    size_t selected_managed[4] = {0};
    if (!actql_native_command_platform_managed_selection(
        &actql_command_entry, selected_managed))
      actql_command_initial_refusal();
    /* Allocator setup may itself emit a diagnostic. Bind the same original
     * static stream buffers before that first covered call, without treating
     * this setup as the allocator/Host admission or a flush acknowledgement. */
    if (!actql_bootstrap_bind_initial_command_output(
        &actql_command_entry.initial_stdio,
        &actql_command_entry.output_control, stdout, stderr))
      actql_command_initial_refusal();
  }
#endif
  /* The same physical binding reads the complete private selection first.
   * Incomplete coverage returns NULL before any allocator call. Once setup
   * starts, retain its same partial receiver rather than reopening a heap.
   * The complete candidate remains unavailable until all initial terms are
   * connected; successful arena setup alone cannot admit the command. */
  actql_command_entry.initial_managed =
    actql_native_initial_managed_begin(&actql_command_entry);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED) {
    /* This source-pinned recipe selects operational Local preparation, rather
     * than a controlled component diagnostic. The real allocator original and
     * the complete same-phase selection are conjunctive before later initializers. */
    if (!actql_command_entry.initial_managed ||
        actql_native_initial_managed_issue(actql_command_entry.initial_managed) != 0 ||
        !actql_native_initial_managed_current(actql_command_entry.initial_managed))
      actql_command_initial_refusal();
    actql_command_entry.initial_envelope_admitted = true;
  }
#endif
#else
  atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_NOT_SELECTED)
    actql_command_initial_refusal();
#endif
#endif
}

/* Main joins its bounded original raw input to this SAME early entry. Neither
 * this observation nor a successful input bound can select operational
 * coverage; only the complete trusted initial envelope can do so. */
void actql_native_client_capture_command_entry(void) {
  if (atomic_load_explicit(&actql_command_entry_state, memory_order_acquire) != 1)
    return;
  if (actql_command_entry.process != getpid() ||
      !pthread_equal(actql_command_entry.thread, pthread_self())) return;
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK ||
      actql_command_entry.source != actql_command_input_source) {
    atomic_store_explicit(&actql_command_entry_state, -1, memory_order_release);
    return;
  }
  atomic_store_explicit(&actql_command_entry_state, 2, memory_order_release);
}

static bool actql_command_entry_thread(
    const actql_native_command_platform_original *entry) {
  return entry == &actql_command_entry &&
    atomic_load_explicit(&actql_command_entry_state, memory_order_acquire) == 2 &&
    entry->process == getpid() && pthread_equal(entry->thread, pthread_self()) &&
    actql_bootstrap_command_stack_current(&entry->initial_stack);
}

actql_native_command_platform_original *
actql_native_command_platform_current(void) {
  actql_native_command_platform_original *entry = &actql_command_entry;
#if defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY)
  if (!entry->initial_managed ||
      !actql_native_initial_managed_current(entry->initial_managed)) return NULL;
  if (!actql_bootstrap_command_output_current(
      &entry->output_control, stdout, stderr)) return NULL;
  if (!actql_bootstrap_command_stdio_current(
      &entry->initial_stdio, stdout, stderr)) return NULL;
#endif
  return actql_command_entry_thread(entry) &&
    entry->initial_envelope_admitted && !entry->closing ? entry : NULL;
}

const char *actql_native_command_platform_scratch_directory(
    actql_native_command_platform_original *entry) {
  return entry && entry == actql_native_command_platform_current()
    ? actql_command_input_scratch : NULL;
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
      kind > ACTQL_NATIVE_COMMAND_CRYPTO_COMPONENT) return NULL;
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

#include "../../platform_native/host_bootstrap/initial_managed.inc"

#endif
