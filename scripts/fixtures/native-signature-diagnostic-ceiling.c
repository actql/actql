// Actual Signature diagnostic C paths with injected loader/OpenSSL callbacks.
// No crypto library, key verification, signing, secret or Provider is used.
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
  (void)path; (void)flags; return NULL;
}
static char *fixture_dlerror(void) { return (char *)injected_detail; }
#define malloc fixture_malloc
#define dlopen fixture_dlopen
#define dlerror fixture_dlerror
#define ACTQL_SIGNATURE_RAW_DIAGNOSTIC
#include "../../src/platform_native/signature/signature_stub.c"
#undef malloc
#undef dlopen
#undef dlerror
static void expect(moonbit_bytes_t bytes, const char *value) {
  size_t n=strlen(value);
  assert((size_t)Moonbit_array_length(bytes)==n);
  assert(n==0 || memcmp(bytes,value,n)==0);
  moonbit_decref(bytes);
}
static BIO *fixture_bio(const void *bytes,int length) {
  assert(bytes!=NULL && length>0); return NULL;
}
static unsigned long fixture_error(void) { return 1; }
static void fixture_error_string(unsigned long code,char *target,size_t size) {
  assert(code==1 && size==256);
  snprintf(target,size,"oversized crypto error");
}
int main(void) {
  actql_native_signature_library library={0};
  library.diagnostic_ceiling=4;
  actql_replace_error(&library,"abcd");
  expect(actql_native_signature_library_error(&library),"abcd");
  puts("exact detail: PASS");
  actql_replace_error(&library,"abcde");
  expect(actql_native_signature_library_error(&library),"");
  puts("one-over omits whole detail: PASS");
  actql_replace_error(&library,"\xc3\xa9\xc3\xa9");
  expect(actql_native_signature_library_error(&library),"\xc3\xa9\xc3\xa9");
  actql_replace_error(&library,"\xc3\xa9\xc3\xa9x");
  expect(actql_native_signature_library_error(&library),"");
  puts("UTF8, no prefix: PASS");
  size_t page=(size_t)sysconf(_SC_PAGESIZE);
  char *pages=mmap(NULL,page*2,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
  assert(pages!=MAP_FAILED && mprotect(pages+page,page,PROT_NONE)==0);
  char *end=pages+page-5;memset(end,'x',5);
  actql_replace_error(&library,end);
  expect(actql_native_signature_library_error(&library),"");
  assert(munmap(pages,page*2)==0);
  puts("bounded scan before first copy: PASS");
  allocation_failure=1;
  actql_replace_error(&library,"ok");
  allocation_failure=0;
  expect(actql_native_signature_library_error(&library),"");
  puts("diagnostic allocation failure: PASS");
  injected_detail="oversized loader error";
  actql_native_signature_library *failed=actql_native_signature_load_library(
    (moonbit_bytes_t)"none",4,4);
  assert(!actql_native_signature_library_ready(failed) && failed->diagnostic_ceiling==4);
  expect(actql_native_signature_library_error(failed),"");
  moonbit_decref(failed);
  puts("loader failure remains failure: PASS");
  library.dynamic_library=(void *)&library;
  library.bio_new_mem_buf=fixture_bio;
  library.err_get_error=fixture_error;
  library.err_error_string_n=fixture_error_string;
  unsigned char signature[86];memset(signature,'A',sizeof(signature));
  assert(actql_native_signature_verify_ed25519(&library,
    (moonbit_bytes_t)"x",1,(moonbit_bytes_t)"m",1,signature,86)==3);
  expect(actql_native_signature_library_error(&library),"");
  puts("crypto refusal code preserved: PASS");
  actql_native_signature_library legacy={0};
  actql_replace_error(&legacy,"legacy detail exceeds four");
  expect(actql_native_signature_library_error(&legacy),"legacy detail exceeds four");
  free(legacy.error);free(library.error);
  puts("legacy diagnostic compatibility: PASS");
  puts("Signature diagnostic cases: 8/8");
  return 0;
}
