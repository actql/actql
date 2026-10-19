#ifndef ACTQL_NATIVE_OBSERVED_COMPONENT_MEMBER_H
#define ACTQL_NATIVE_OBSERVED_COMPONENT_MEMBER_H
#include "../host_bootstrap/command_platform.h"

/* The loaded symbol's image path must still name the same original file.
 * Component callers separately check every fixed symbol's common image base.
 * This observation supplies neither initial coverage nor load permission. */
int actql_native_observed_component_member_image(
  actql_native_observed_component_member *member, const char *image_path);
#endif
