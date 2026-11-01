#ifndef ACTQL_HTTP_COMPONENT_TLS_LIFETIME_H
#define ACTQL_HTTP_COMPONENT_TLS_LIFETIME_H

#include <stdint.h>
#include <stddef.h>

// Fixed callbacks into the same executable's original Read provider. The
// component copies this binding, never a Library pointer or a new allocator.
typedef struct {
  void *read;
  void *lease;
  void *(*allocate)(void *, void *, size_t);
  void *(*reallocate)(void *, void *, void *, size_t);
  void (*retire)(void *, void *, void *);
} actql_http_component_memory;

// Private physical-component ABI, not a Host, permission or public curl API.
// The installed Library retains the original table and its loader reference.
typedef struct {
  uint32_t abi;
  uint32_t bytes;
  // -1: no reference acquired; 0: initialized; 1: original failed initializer
  // retained for release. A partial acquisition is never a ready Library.
  int (*acquire)(const actql_http_component_memory *);
  void (*cleanup_thread)(void);
  int (*release)(void);
  void *(*allocate)(size_t);
  void (*retire)(void *);
  void *(*reallocate)(void *, size_t);
  char *(*duplicate)(const char *);
  void *(*allocate_zeroed)(size_t, size_t);
} actql_http_component_tls_api;

typedef const actql_http_component_tls_api *(*actql_http_component_tls_api_fn)(void);

#endif
