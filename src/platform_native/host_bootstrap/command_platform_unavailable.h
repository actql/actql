#ifndef ACTQL_NATIVE_COMMAND_PLATFORM_UNAVAILABLE_H
#define ACTQL_NATIVE_COMMAND_PLATFORM_UNAVAILABLE_H

#include "command_platform.h"
#include <stddef.h>

/* Existing bootstrap Owner's unselected entrance. Non-CLI providers do not
 * depend on argv, the executable entry or the filesystem member owner merely
 * to report Unavailable. The selected executable supplies strong definitions
 * from its actual entry. These defaults can never create an original, perform
 * a load, acknowledge cleanup or select a replacement Library. */
__attribute__((weak)) actql_native_command_platform_original *
actql_native_command_platform_current(void) { return NULL; }

bool actql_native_command_platform_available(void) {
  return actql_native_command_platform_current() != NULL;
}

__attribute__((weak)) actql_native_command_platform_load *
actql_native_command_platform_begin_load(
    actql_native_command_platform_original *original,
    enum actql_native_command_component_kind kind,
    actql_native_observed_component_member *member) {
  (void)original; (void)kind; (void)member;
  return NULL;
}

__attribute__((weak)) int actql_native_command_platform_observe_load(
    actql_native_command_platform_load *load, void *module) {
  (void)load; (void)module;
  return 0;
}

__attribute__((weak)) int actql_native_command_platform_load_current(
    actql_native_command_platform_load *load) {
  (void)load;
  return 0;
}

__attribute__((weak)) int actql_native_command_platform_module_released(
    actql_native_command_platform_load *load, void *module) {
  (void)load; (void)module;
  return 0;
}

#endif
