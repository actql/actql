#include "moonbit.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int32_t actql_native_client_measure_prearguments(int32_t,int32_t,int32_t,int32_t);
extern int32_t actql_native_client_preargument_count(void);
extern int32_t actql_native_client_preargument_storage_bytes(void);
extern int32_t actql_native_client_preargument_context_bytes(void);
extern int32_t actql_native_client_copy_preargument_source(moonbit_bytes_t,int32_t);
extern int32_t actql_native_client_copy_preargument_context(moonbit_bytes_t,int32_t);
int main(int argc, char **argv) {
  assert(argc == 2);
  const char *name = argv[1];
  int expected = strcmp(name,"absent") == 0 ? 5 :
    strcmp(name,"missing-source") == 0 ? 6 :
    strcmp(name,"context-limit") == 0 ? 7 :
    strcmp(name,"invalid-bound") == 0 ? 1 : 0;
  int status = actql_native_client_measure_prearguments(
    strcmp(name,"invalid-bound") == 0 ? 0 : 256,4096,65536,
    strcmp(name,"context-limit") == 0 ? 1 : 8192);
  assert(status == expected);
  unsigned char source[40] = {0}, context[128] = {0};
  if (status == 0) {
    int storage = 0;
    for (int i=0;i<argc;++i) storage += (int)strlen(argv[i])+1;
    const char *original = getenv("ACTQL_NATIVE_LOCAL_RUNTIME");
    assert(original != NULL && strlen(original) < sizeof(context));
    assert(actql_native_client_preargument_count() == argc);
    assert(actql_native_client_preargument_storage_bytes() == storage);
    assert(actql_native_client_preargument_context_bytes() == (int)strlen(original));
    assert(actql_native_client_copy_preargument_source(source,40));
    assert(memcmp(source,"1234567890abcdef1234567890abcdef12345678",40)==0);
    assert(!actql_native_client_copy_preargument_context(context,(int)strlen(original)+1));
    assert(actql_native_client_copy_preargument_context(context,(int)strlen(original)));
    assert(memcmp(context,original,strlen(original))==0);
  } else {
    assert(actql_native_client_preargument_count() == -1);
    assert(actql_native_client_preargument_storage_bytes() == -1);
    assert(actql_native_client_preargument_context_bytes() == -1);
    assert(!actql_native_client_copy_preargument_source(source,40));
    assert(!actql_native_client_copy_preargument_context(context,1));
  }
  // A second call never restarts a selected or refused observation.
  assert(actql_native_client_measure_prearguments(1,1,1,1) == expected);
  puts("original preargument wrapper passed");
  return 0;
}
