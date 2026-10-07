/* Borrow actual driver roots synchronously. No address is retained or used
 * after the call; a cleared root is not evidence of physical GC destruction. */
#include "moonbit.h"
#include <assert.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
extern const uint32_t *moonbit_layout_table;
moonbit_string_t actql_proof_driver_retirement(void *root,int32_t task,int32_t phase) {
  assert(root && sizeof(void*)==8 && phase>=0 && phase<=4 && task>=0);
  assert(Moonbit_object_kind(root)==moonbit_BLOCK_KIND_REGULAR);
  uint32_t meta=Moonbit_object_header(root)->meta;
  assert((meta>>MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT)==MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED);
  const uint32_t *s=moonbit_layout_table+((meta>>MOONBIT_REGULAR_LAYOUT_INDEX_SHIFT)&MOONBIT_REGULAR_LAYOUT_INDEX_MASK);
  assert(s[0]==2 && s[1]==1 && s[2]==0);
  void *provider;memcpy(&provider,root,sizeof provider);
  char text[512];int n=snprintf(text,sizeof text,
    "ACTQL_DRIVER_ROOT:{\"task\":%d,\"phase\":%d,\"root\":\"%" PRIu64 "\",\"rootRequestedBytes\":%u,\"provider\":",
    task,phase,(uint64_t)(uintptr_t)root,8+s[0]*4);
  assert(n>0 && (size_t)n<sizeof text);
  int m=provider?snprintf(text+n,sizeof text-n,"\"%" PRIu64 "\"}",(uint64_t)(uintptr_t)provider):snprintf(text+n,sizeof text-n,"null}");
  assert(m>0 && (size_t)m<sizeof text-n);n+=m;
  moonbit_string_t out=moonbit_make_string_raw(n);
  for(int i=0;i<n;i++)out[i]=(uint16_t)(unsigned char)text[i];
  return out;
}
