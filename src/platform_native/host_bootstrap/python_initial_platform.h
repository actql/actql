#ifndef ACTQL_NATIVE_PYTHON_INITIAL_PLATFORM_H
#define ACTQL_NATIVE_PYTHON_INITIAL_PLATFORM_H
#include <stdbool.h>
#include <stddef.h>

/* Private Python operational entrance in the existing Bootstrap Owner.
 * This original is not the Native command original or a serialized selection.
 * Its trusted entry must bind the actual interpreter/process/thread, selected
 * component/recipe and one initial generation before the covered first call.
 * Later Hosts borrow that same lifetime; they cannot create another baseline.
 */
typedef struct actql_native_python_initial_platform_original
  actql_native_python_initial_platform_original;
typedef struct actql_native_initial_managed_original
  actql_native_initial_managed_original;

/* Read only the same actual entry's selected finite facility. The four DATA
 * slots retain the physical implementation's payload, external metadata and
 * alignment coverage, maximum request and setups=1 meanings. They do not
 * issue the original, complete outside-arena coverage or Worker capacity.
 * Missing/foreign/non-current entry refuses without changing the slots.
 */
bool actql_native_python_initial_platform_managed_selection(
  actql_native_python_initial_platform_original *entry, size_t out[4]);

/* Include initial_managed.inc once with the Python operational entry selected.
 * It reuses the physical implementation with this distinct typed original.
 * The selected derived component must have no automatic MI/Moon initializer:
 * a refused or partial entry must not fall through to an unfunded initializer.
 * A partial attempt returns its original close-only carrier, never a retry.
 */
actql_native_initial_managed_original *actql_native_python_initial_managed_begin(
  actql_native_python_initial_platform_original *entry);
bool actql_native_initial_managed_current(
  actql_native_initial_managed_original *original);
/* Selected component-internal initialization fence. This observes only the
 * one entrance's actual original; no caller-provided pointer can substitute
 * another arena. It neither acquires initial coverage nor acknowledges it. */
bool actql_native_python_initial_managed_current(void);
int actql_native_initial_managed_issue(
  actql_native_initial_managed_original *original);

/* Restoring the prior default is not mapping/registration/process retirement.
 * Escaped allocations and metadata retain their original process lifetime.
 */
int actql_native_initial_managed_restore(
  actql_native_initial_managed_original *original);
#endif
