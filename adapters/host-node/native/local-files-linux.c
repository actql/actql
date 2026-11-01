/* Normal Linux Local Files image. Share the complete reader/writer custody
 * implementation; the separate APFS HostJournal inspector is not exported. */
#include <node_api.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "napi-filesystem-helpers.inc"
#include "../../connectors/local/site/root-filesystem.inc"

static napi_value initialize(napi_env env, napi_value exports) {
  if (!initialize_local_files(env, exports) || napi_object_freeze(env, exports) != napi_ok) return NULL;
  return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME, initialize)
