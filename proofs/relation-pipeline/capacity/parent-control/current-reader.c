/* Synchronous borrowed census of actual objects. Addresses are diagnostic
 * tokens, never retained C pointers. Scalar GC metadata cannot supply a byte
 * extent: only the explicit single-field Ref premise applies to those leaves. */
#include "moonbit.h"
#include <assert.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
extern const uint32_t *moonbit_layout_table;
static const uint32_t *current_shape(void *p) {
  assert(p && Moonbit_object_kind(p)==moonbit_BLOCK_KIND_REGULAR);
  struct moonbit_object *h=Moonbit_object_header(p);
  assert((h->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT)==MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED);
  return moonbit_layout_table+((h->meta >> MOONBIT_REGULAR_LAYOUT_INDEX_SHIFT)&MOONBIT_REGULAR_LAYOUT_INDEX_MASK);
}
static void *current_pointer(void *p,uint32_t offset) {
  void *r;memcpy(&r,(uint8_t*)p+offset,sizeof r);return r;
}
static uint64_t current_id(void *p) {return (uint64_t)(uintptr_t)p;}
struct current_json {char text[16384];size_t used;};
static void current_add(struct current_json *j,const char *f,...) {
  va_list args;va_start(args,f);int n=vsnprintf(j->text+j->used,sizeof j->text-j->used,f,args);va_end(args);
  assert(n>0 && (size_t)n<sizeof j->text-j->used);j->used+=(size_t)n;
}
static moonbit_string_t current_string(struct current_json *j) {
  moonbit_string_t s=moonbit_make_string_raw((int32_t)j->used);
  for(size_t i=0;i<j->used;i++)s[i]=(uint16_t)(unsigned char)j->text[i];return s;
}
static int current_contains(void **a,int count,void *p) {
  for(int i=0;i<count;i++)if(a[i]==p)return 1;return 0;
}
static void current_record(struct current_json *j,void *p) {
  const uint32_t *s=current_shape(p);
  current_add(j,"{\"id\":\"%" PRIu64 "\",\"requestedBytes\":%u,\"captures\":[",current_id(p),8+s[0]*4);
  for(uint32_t i=0;i<s[1];i++) {
    uint32_t tagged=s[2+i];assert(!(tagged&1));uint32_t offset=(tagged>>1)*4;
    assert(offset+8<=s[0]*4);
    current_add(j,"%s{\"offset\":%u,\"id\":%s",i?",":"",offset,
      current_pointer(p,offset)?"\"":"null");
    if(current_pointer(p,offset))current_add(j,"%" PRIu64 "\"",current_id(current_pointer(p,offset)));
    current_add(j,"}");
  }
  current_add(j,"]}");
}
static void current_callbacks(struct current_json *j,void *parent) {
  const uint32_t *s=current_shape(parent);assert(s[0]==12 && s[1]==6);
  for(int i=0;i<6;i++)assert(s[2+i]==(uint32_t)i*4);
  current_add(j,",\"callbacks\":[");
  for(int i=0;i<5;i++) {if(i)current_add(j,",");current_record(j,current_pointer(parent,i<4?8*i:40));}
  current_add(j,"]");
}
static void current_array(struct current_json *j,const char *name,void *a,int outputs) {
  const uint32_t *s=current_shape(a);assert(s[0]==4 && s[1]==1 && s[2]==0);
  void *b=current_pointer(a,0);int32_t length;memcpy(&length,(uint8_t*)a+8,4);
  assert(Moonbit_object_kind(b)==moonbit_BLOCK_KIND_REF_ARRAY);
  int32_t slots=Moonbit_array_length(b);assert(length>=0 && slots>=length && length<=128);
  current_add(j,",\"%s\":{\"id\":\"%" PRIu64 "\",\"backing\":\"%" PRIu64 "\",\"length\":%d,\"slots\":%d,\"ownerBytes\":24,\"backingBytes\":%d,\"staticBacking\":%s,\"elements\":[",name,current_id(a),current_id(b),length,slots,8+8*slots,Moonbit_rc_count(Moonbit_object_header(b))<0?"true":"false");
  for(int i=0;i<length;i++) {
    void *p=current_pointer(b,(uint32_t)i*8);
    if(p) current_add(j,"%s\"%" PRIu64 "\"",i?",":"",current_id(p));
    else current_add(j,"%snull",i?",":"");
  }
  current_add(j,"]");
  if(outputs) {
    current_add(j,",\"completions\":[");
    for(int i=0;i<length;i++) {
      void *p=current_pointer(b,(uint32_t)i*8);
      if(p) {const uint32_t *o=current_shape(p);assert(o[1]>0 && o[2]==0);current_add(j,"%s\"%" PRIu64 "\"",i?",":"",current_id(current_pointer(p,0)));}
      else current_add(j,"%snull",i?",":"");
    }
    current_add(j,"]");
  }
  current_add(j,"}");
}
moonbit_string_t actql_proof_current_chain_start(void *parent,void *state,
  void *used,void *cancelled,void *terminal,void *reclaimed,void *cleanup_index,
  void *sequence,void *inputs,void *execution,void *measurement,void *numeric,void *family,
  int32_t count,int32_t max_value_bytes,int32_t reclaims_scratch) {
  struct current_json j={.used=0};
  const char *names[12]={"state","used","cancelled","terminal","reclaimed","cleanupIndex","sequence","inputs","execution","measurement","numeric","family"};
  void *known[12]={state,used,cancelled,terminal,reclaimed,cleanup_index,sequence,inputs,execution,measurement,numeric,family};
  current_add(&j,"ACTQL_CHAIN_NATIVE:{\"kind\":\"startup\",\"parent\":\"%" PRIu64 "\",\"count\":%d,\"maxValueBytes\":%d,\"reclaimsScratch\":%s,\"roots\":{",current_id(parent),count,max_value_bytes,reclaims_scratch?"true":"false");
  for(int i=0;i<12;i++) {
    current_add(&j,"%s\"%s\":",i?",":"",names[i]);
    if(known[i])current_add(&j,"\"%" PRIu64 "\"",current_id(known[i]));else current_add(&j,"null");
  }
  current_add(&j,"},\"state\":");current_record(&j,state);current_callbacks(&j,parent);
  void *unknown[16];int n=0;
  for(int i=0;i<5;i++) {
    void *cb=current_pointer(parent,i<4?8*i:40);const uint32_t *s=current_shape(cb);
    for(uint32_t k=0;k<s[1];k++) {
      assert(!(s[2+k]&1));void *capture=current_pointer(cb,(s[2+k]>>1)*4);
      if(capture && !current_contains(known,12,capture) && !current_contains(unknown,n,capture)) {
        assert(n<16);unknown[n++]=capture;
      }
    }
  }
  current_add(&j,",\"environments\":[");
  for(int i=0;i<n;i++){if(i)current_add(&j,",");current_record(&j,unknown[i]);}
  current_add(&j,"]}");return current_string(&j);
}
moonbit_string_t actql_proof_current_chain_phase(void *parent,void *state,void *children,
  void *completed,void *preparation,void *read,int32_t position,int32_t pending,int32_t reclaiming,int32_t phase) {
  struct current_json j={.used=0};
  current_add(&j,"ACTQL_CHAIN_NATIVE:{\"kind\":\"phase\",\"phase\":%d,\"parent\":\"%" PRIu64 "\",\"position\":%d,\"pending\":%s,\"reclaiming\":%s,\"state\":",phase,current_id(parent),position,pending?"true":"false",reclaiming?"true":"false");
  current_record(&j,state);current_callbacks(&j,parent);
  current_array(&j,"children",children,0);current_array(&j,"completed",completed,1);
  current_add(&j,",\"preparation\":");if(preparation)current_record(&j,preparation);else current_add(&j,"null");
  current_add(&j,",\"read\":");if(read)current_record(&j,read);else current_add(&j,"null");
  current_add(&j,"}");return current_string(&j);
}

/* These routes borrow typed cursor/ProducerRead roots. The selected element
 * representation is eight-byte reference storage; columns use four-byte Int
 * storage. Read only the first previously initialized slot after clear, never
 * arbitrary uninitialized capacity or a transitive heap graph. */
static void current_storage_array(struct current_json *j,const char *name,
  void *a,int element) {
  const uint32_t *s=current_shape(a);assert(s[0]==4 && s[1]==1 && s[2]==0);
  void *b=current_pointer(a,0);int32_t len;memcpy(&len,(uint8_t*)a+8,4);
  int32_t slots=Moonbit_array_length(b);assert(len>=0 && len<=slots && slots<=128);
  assert(Moonbit_object_kind(b)==(element==4?moonbit_BLOCK_KIND_VAL_ARRAY:moonbit_BLOCK_KIND_REF_ARRAY));
  current_add(j,",\"%s\":{\"owner\":\"%" PRIu64 "\",\"backing\":\"%" PRIu64 "\",\"length\":%d,\"slots\":%d,\"elementBytes\":%d,\"ownerBytes\":24,\"backingBytes\":%d,\"staticBacking\":%s,\"firstInitialized\":",name,current_id(a),current_id(b),len,slots,element,8+element*slots,Moonbit_rc_count(Moonbit_object_header(b))<0?"true":"false");
  if(slots==0)current_add(j,"null");
  else if(element==4) {int32_t first;memcpy(&first,b,4);current_add(j,"%d",first);}
  else {void *first=current_pointer(b,0);assert(first);current_add(j,"\"%" PRIu64 "\"",current_id(first));}
  current_add(j,"}");
}
int32_t actql_proof_current_columns_count(void *read) {
  const uint32_t *s=current_shape(read);assert(s[0]==22 && s[1]==5);
  void *a=current_pointer(read,16);int32_t len;memcpy(&len,(uint8_t*)a+8,4);return len;
}
moonbit_string_t actql_proof_current_preparation_storage(void *prep,void *read,
  void *transferred,int32_t phase,int32_t ports,int32_t fields) {
  struct current_json j={.used=0};
  assert(ports==1 && fields==1); /* fixed independent fixture contract */
  current_add(&j,"ACTQL_PREPARATION_STORAGE:{\"phase\":%d,\"ports\":%d,\"fields\":%d,\"preparation\":",phase,ports,fields);
  current_record(&j,prep);current_add(&j,",\"read\":");current_record(&j,read);
  current_storage_array(&j,"selected",current_pointer(prep,32),8);
  current_storage_array(&j,"columns",current_pointer(read,16),4);
  current_add(&j,",\"transferred\":");if(transferred)current_record(&j,transferred);else current_add(&j,"null");
  current_add(&j,",\"transferredColumns\":");
  if(transferred)current_add(&j,"\"%" PRIu64 "\"",current_id(current_pointer(transferred,16)));
  else current_add(&j,"null");
  current_add(&j,"}");return current_string(&j);
}
