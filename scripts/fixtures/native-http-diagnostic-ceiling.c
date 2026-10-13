// Actual HTTP diagnostic C paths with injected callbacks. No libcurl, TLS,
// credential file, Provider send or Run reconciliation is performed.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static const char *injected_detail;
static int allocation_failure;
static void *fixture_malloc(size_t n) {
  return allocation_failure ? NULL : malloc(n);
}
static void *fixture_dlopen(const char *path, int flags) {
  (void)path; (void)flags;
  return NULL;
}
static char *fixture_dlerror(void) { return (char *)injected_detail; }
#define malloc fixture_malloc
#define dlopen fixture_dlopen
#define dlerror fixture_dlerror
#include "../../src/platform_native/http_client/http_client_stub.c"
#undef malloc
#undef dlopen
#undef dlerror
// This fixture has no original private-file installation. Those link seams
// must never be reached; they provide neither a descriptor nor permission.
int actql_native_private_file_projection_open(
  actql_native_private_file_projection *projection
) { (void)projection; abort(); }
bool actql_native_private_file_projection_matches(
  actql_native_private_file_projection *projection, int descriptor
) { (void)projection; (void)descriptor; abort(); }
static void expect(moonbit_bytes_t bytes, const char *value) {
  size_t n = strlen(value);
  assert((size_t)Moonbit_array_length(bytes) == n);
  assert(n == 0 || memcmp(bytes, value, n) == 0);
  moonbit_decref(bytes);
}
static const char *fixture_strerror(CURLcode code) {
  (void)code; return injected_detail;
}
static int perform_code;
static int performs;
static CURL *fixture_init(void) { return (CURL *)&performs; }
static CURLcode fixture_setopt(CURL *curl, CURLoption option, ...) {
  assert(curl != NULL); (void)option; return ACTQL_CURLE_OK;
}
static CURLcode fixture_perform(CURL *curl) {
  assert(curl != NULL); performs++; return perform_code;
}
static curl_slist *fixture_append(curl_slist *list, const char *value) {
  (void)list; assert(value != NULL); return (curl_slist *)&performs;
}
static void fixture_free(curl_slist *list) { (void)list; }
static void fixture_cleanup(CURL *curl) { assert(curl != NULL); }
int main(void) {
  actql_native_http_library library = {0};
  library.dynamic_library = (void *)&library;
  library.diagnostic_ceiling = 4;
  library.easy_strerror = fixture_strerror;
  actql_native_http_client client = {0};
  client.library = &library;
  client.diagnostic_ceiling = library.diagnostic_ceiling;
  atomic_init(&client.cancelled, false);
  actql_set_client_error(&client, "abcd");
  expect(actql_native_http_client_error(&client), "abcd");
  assert(client.error_present && !actql_native_http_client_ready(&client));
  puts("exact detail: PASS");
  actql_set_client_error(&client, "abcde");
  expect(actql_native_http_client_error(&client), "");
  assert(client.error_present && !actql_native_http_client_ready(&client));
  puts("one-over preserves error fact: PASS");
  actql_set_client_error(&client, "\xc3\xa9\xc3\xa9");
  expect(actql_native_http_client_error(&client), "\xc3\xa9\xc3\xa9");
  actql_set_client_error(&client, "\xc3\xa9\xc3\xa9x");
  expect(actql_native_http_client_error(&client), "");
  puts("UTF8, no prefix: PASS");
  size_t page=(size_t)sysconf(_SC_PAGESIZE);
  char *pages=mmap(NULL,page*2,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
  assert(pages!=MAP_FAILED && mprotect(pages+page,page,PROT_NONE)==0);
  char *end=pages+page-5; memset(end,'x',5);
  actql_set_client_error(&client,end);
  expect(actql_native_http_client_error(&client), "");
  assert(munmap(pages,page*2)==0);
  puts("bounded scan before copy: PASS");
  allocation_failure=1;
  actql_set_client_error(&client,"ok");
  allocation_failure=0;
  assert(client.error_present && !actql_native_http_client_ready(&client));
  expect(actql_native_http_client_error(&client), "");
  puts("allocation failure preserves refusal: PASS");
  // Actual initializers inherit the same selected ceiling, including failures.
  injected_detail="oversized loader detail";
  actql_native_http_library *failed=actql_native_http_load_library(
    (moonbit_bytes_t)"none",4,4);
  assert(!actql_native_http_library_ready(failed) && failed->diagnostic_ceiling==4);
  expect(actql_native_http_library_error(failed), "");
  actql_native_http_client *created=actql_native_http_create_authenticated_client(
    failed,(moonbit_bytes_t)"ca",2,NULL,0,NULL,0,(moonbit_bytes_t)"secret",6,0,1,1);
  assert(created->diagnostic_ceiling==4 && created->error_present);
  assert(!actql_native_http_client_ready(created));
  expect(actql_native_http_client_error(created), "");
  moonbit_decref(created); moonbit_decref(failed);
  puts("Library to Client inheritance and constructor failure: PASS");
  client.max_response_bytes=0;
  library.easy_init=fixture_init; library.easy_setopt=fixture_setopt;
  library.easy_perform=fixture_perform; library.slist_append=fixture_append;
  library.slist_free_all=fixture_free; library.easy_cleanup=fixture_cleanup;
  perform_code=1;
  assert(actql_native_http_client_post_json(&client,
    (moonbit_bytes_t)"https://e.test",14,NULL,0)==-1);
  assert(performs==1 && client.error_present);
  expect(actql_native_http_client_error(&client), "");
  puts("transport failure is not success: PASS");
  assert(actql_native_http_client_cancel(&client));
  assert(actql_native_http_client_post_json(&client,NULL,0,NULL,0)==2);
  assert(performs==1);
  assert(actql_native_http_client_close(&client));
  assert(actql_native_http_client_post_json(&client,NULL,0,NULL,0)==3);
  assert(!actql_native_http_client_close(&client));
  assert(client.closed && client.response==NULL);
  puts("cancel and close classifications unchanged: PASS");
  actql_native_http_library legacy={0};
  actql_replace_error(&legacy.error,legacy.diagnostic_ceiling,"legacy detail exceeds four");
  expect(actql_native_http_library_error(&legacy),"legacy detail exceeds four");
  free(legacy.error);
  puts("legacy diagnostic compatibility: PASS");
  puts("HTTP diagnostic cases: 9/9");
  return 0;
}
