/* A synchronous borrowed observation of a managed parent. It stores no
 * object pointer, traverses no child payload and changes no reference count.
 * Scalar payload ceilings come from the explicit source/ABI Ref premise,
 * not from a size measurement that the scalar GC header cannot provide. */
static const uint32_t *parent_indexed_shape(void *object) {
  if (!object || Moonbit_object_kind(object) != moonbit_BLOCK_KIND_REGULAR)
    return NULL;
  if ((Moonbit_object_header(object)->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT)
      != MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED) return NULL;
  return layout(object);
}
static void *parent_pointer_at(void *object, uint32_t offset) {
  void *value; memcpy(&value, (uint8_t *)object + offset, sizeof value); return value;
}
static int32_t parent_int_at(void *object) {
  int32_t value; memcpy(&value, object, sizeof value); return value;
}
static int32_t parent_bool_at(void *object) {
  uint8_t value; memcpy(&value,object,sizeof value);assert(value<=1);return value;
}
static void parent_append_ids(char *json, size_t size, size_t *used,
                              const char *key, void **objects, int count) {
  int written = snprintf(json + *used, size - *used, ",\"%s\":[", key);
  assert(written > 0 && (size_t)written < size - *used); *used += (size_t)written;
  for (int i=0; i<count; i++) {
    written = snprintf(json + *used, size - *used, "%s\"%" PRIu64 "\"",
      i ? "," : "", (uint64_t)(uintptr_t)objects[i]);
    assert(written > 0 && (size_t)written < size - *used); *used += (size_t)written;
  }
  written = snprintf(json + *used, size - *used, "]");
  assert(written > 0 && (size_t)written < size - *used); *used += (size_t)written;
}
moonbit_string_t actql_proof_parent_phase(void *parent, int32_t phase) {
  const uint32_t *owner_shape = parent_indexed_shape(parent);
  assert(owner_shape && owner_shape[0] == 12 && owner_shape[1] == 6);
  void *callbacks[5];
  for (int i=0;i<5;i++) callbacks[i]=parent_pointer_at(parent, i<4 ? (uint32_t)i*8 : 40);
  const uint32_t *advance_shape=parent_indexed_shape(callbacks[0]);
  // Other actual child/provider owners remain outside this parent component.
  if (!advance_shape || advance_shape[0]!=22 || advance_shape[1]!=9)
    return moonbit_make_string_raw(0);
  void *environment=parent_pointer_at(callbacks[0],8);
  const uint32_t *env_shape=parent_indexed_shape(environment);
  if (!env_shape || env_shape[0]!=28 || env_shape[1]!=12)
    return moonbit_make_string_raw(0);
  const uint32_t *cleanup_shape=parent_indexed_shape(callbacks[3]);
  assert(cleanup_shape && cleanup_shape[0]==14 && cleanup_shape[1]==6);
  void *roots[11]={parent,
    parent_pointer_at(environment,40), parent_pointer_at(environment,32),
    parent_pointer_at(environment,24), parent_pointer_at(environment,16),
    parent_pointer_at(environment,8), parent_pointer_at(environment,0),
    parent_pointer_at(callbacks[0],24), parent_pointer_at(callbacks[0],16),
    parent_pointer_at(callbacks[3],16), parent_pointer_at(callbacks[3],8)};
  uint32_t captured_offsets[12]={0,8,16,24,32,40,48,56,64,80,88,96};
  for(int i=0;i<12;i++) assert(env_shape[2+i]==captured_offsets[i]/2);
  void *expected_advance[9]={environment,roots[8],roots[7],roots[6],roots[5],roots[4],roots[3],roots[2],parent_pointer_at(environment,80)};
  for(int i=0;i<9;i++) {
    assert(advance_shape[2+i]==(uint32_t)(i+1)*4);
    assert(parent_pointer_at(callbacks[0],(uint32_t)(i+1)*8)==expected_advance[i]);
  }
  void *expected_cleanup[6]={roots[10],roots[9],roots[8],roots[3],roots[2],roots[1]};
  for(int i=0;i<6;i++) {
    assert(cleanup_shape[2+i]==(uint32_t)(i+1)*4);
    assert(parent_pointer_at(callbacks[3],(uint32_t)(i+1)*8)==expected_cleanup[i]);
  }
  void *seen[20];int seen_count=0,scalar_refs=0;uint64_t indexed=0;
  for(int i=0;i<11;i++) {
    assert(roots[i] && !has_pointer(seen,seen_count,roots[i]));seen[seen_count++]=roots[i];
    assert(Moonbit_rc_count(Moonbit_object_header(roots[i]))>=0);
    const uint32_t *s=parent_indexed_shape(roots[i]);
    if(i==0) indexed+=regular_bytes(roots[i]);
    else if(i<=3) { assert(s && s[0]==2 && s[1]==1 && s[2]==0); indexed+=regular_bytes(roots[i]); }
    else {
      assert(!s && Moonbit_object_kind(roots[i])==moonbit_BLOCK_KIND_REGULAR);
      assert((Moonbit_object_header(roots[i])->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT)==MOONBIT_REGULAR_LAYOUT_CLASS_SCALAR);
      scalar_refs++;
    }
  }
  assert(scalar_refs==7);
  uint32_t callback_words[5]={22,8,4,14,4};
  for(int i=0;i<5;i++) {
    assert(!has_pointer(seen,seen_count,callbacks[i]));seen[seen_count++]=callbacks[i];
    assert(Moonbit_rc_count(Moonbit_object_header(callbacks[i]))>=0);
    const uint32_t *s=parent_indexed_shape(callbacks[i]);assert(s && s[0]==callback_words[i]);
    indexed+=regular_bytes(callbacks[i]);
  }
  assert(!has_pointer(seen,seen_count,environment));seen[seen_count++]=environment;
  assert(Moonbit_rc_count(Moonbit_object_header(environment))>=0);indexed+=regular_bytes(environment);
  void *reported=parent_pointer_at(parent,32);
  assert(reported && !has_pointer(seen,seen_count,reported));seen[seen_count++]=reported;
  assert(Moonbit_object_kind(reported)==moonbit_BLOCK_KIND_REGULAR && !parent_indexed_shape(reported));
  assert((Moonbit_object_header(reported)->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT)==MOONBIT_REGULAR_LAYOUT_CLASS_SCALAR);
  void *array=parent_pointer_at(roots[1],0);const uint32_t *a=parent_indexed_shape(array);
  assert(a && a[0]==4 && a[1]==1 && a[2]==0);
  assert(!has_pointer(seen,seen_count,array));seen[seen_count++]=array;
  assert(Moonbit_rc_count(Moonbit_object_header(array))>=0);indexed+=regular_bytes(array);
  void *backing=parent_pointer_at(array,0);
  assert(backing && !has_pointer(seen,seen_count,backing));
  assert(Moonbit_object_kind(backing)==moonbit_BLOCK_KIND_REF_ARRAY);
  int32_t count;memcpy(&count,(uint8_t*)environment+104,sizeof count);
  int32_t length;memcpy(&length,(uint8_t*)array+8,sizeof length);
  int32_t slots=Moonbit_array_length(backing);
  assert(count>=2 && length>=0 && length<=count && slots>=length);
  int is_static=Moonbit_rc_count(Moonbit_object_header(backing))<0;
  assert(!is_static || slots==0);
  uint64_t storage=8+8*(uint64_t)slots;
  uint64_t dynamic=is_static ? 0 : storage;
  char json[4096];
  int n=snprintf(json,sizeof json,"ACTQL_PIPELINE_FAULT:{\"kind\":\"parent core observation\",\"phase\":%d,\"parent\":\"%" PRIu64 "\",\"environment\":\"%" PRIu64 "\",\"count\":%d,\"position\":%d,\"pending\":%d,\"terminal\":%d,\"reclaimed\":%d,\"children\":%d,\"childrenSlots\":%d,\"array\":\"%" PRIu64 "\",\"backing\":\"%" PRIu64 "\",\"staticBacking\":%s,\"backingStorageBytes\":%" PRIu64 ",\"dynamicBackingBytes\":%" PRIu64 ",\"indexedBytes\":%" PRIu64 ",\"scalarRefs\":%d,\"reportedScalar\":true",
    phase,(uint64_t)(uintptr_t)parent,(uint64_t)(uintptr_t)environment,count,
    parent_int_at(roots[4]),parent_bool_at(roots[5]),parent_bool_at(roots[8]),parent_bool_at(roots[9]),
    length,slots,(uint64_t)(uintptr_t)array,(uint64_t)(uintptr_t)backing,is_static?"true":"false",storage,dynamic,indexed,scalar_refs);
  assert(n>0 && (size_t)n<sizeof json);size_t used=(size_t)n;
  parent_append_ids(json,sizeof json,&used,"roots",roots,11);
  parent_append_ids(json,sizeof json,&used,"callbacks",callbacks,5);
  n=snprintf(json+used,sizeof json-used,"}");assert(n>0 && (size_t)n<sizeof json-used);used+=(size_t)n;
  moonbit_string_t result=moonbit_make_string_raw((int32_t)used);
  for(size_t i=0;i<used;i++) result[i]=(uint16_t)(unsigned char)json[i];
  return result;
}
