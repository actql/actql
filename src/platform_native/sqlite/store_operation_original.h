#ifndef ACTQL_NATIVE_SQLITE_STORE_OPERATION_ORIGINAL_H
#define ACTQL_NATIVE_SQLITE_STORE_OPERATION_ORIGINAL_H
#include <stdint.h>
/* Private fixed coordinator ABI. FuncRef supplies a compiled trampoline, not
 * a closure layout. Both arguments are retained originals; callback arguments
 * are borrowed under the selected generated FuncRef convention. */
typedef int32_t (*actql_native_store_operation_route)(void *, void *, int32_t);
typedef int32_t (*actql_native_store_delivery_construction)(void *, void *, int32_t);
void *actql_native_sqlite_prepare_store_operation(
  void *, void *, actql_native_store_operation_route);
void *actql_native_sqlite_prepare_store_operation_with_delivery_construction(
  void *, void *, actql_native_store_operation_route,
  actql_native_store_delivery_construction);
#endif
