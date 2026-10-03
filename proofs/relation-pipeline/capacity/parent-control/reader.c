/* Investigation reader: owned roots and callbacks only. Unknown captures are
 * reported separately and are not counted as a proved owned footprint. */
static uint64_t parent_regular_extent(void *object, uint64_t scalar_minimum) {
  assert(Moonbit_object_kind(object) == moonbit_BLOCK_KIND_REGULAR);
  struct moonbit_object *h = Moonbit_object_header(object);
  uint32_t cls = h->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT;
  if (cls == MOONBIT_REGULAR_LAYOUT_CLASS_SCALAR) return 8 + scalar_minimum;
  assert(cls == MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED);
  return regular_bytes(object);
}
static int has_pointer(void **items, int count, void *value) {
  for (int i=0; i<count; i++) if (items[i] == value) return 1;
  return 0;
}
moonbit_string_t actql_proof_parent_control(void *parent, void *children,
  void *previous, void *current, void *position, void *pending, void *used,
  void *cancelled, void *terminal, void *reclaimed, void *cleanup_index,
  void *sequence, void *inputs, void *execution, void *measurement,
  void *numeric, void *family, int32_t count) {
  void *roots[11] = {parent,children,previous,current,position,pending,used,
    cancelled,terminal,reclaimed,cleanup_index};
  uint64_t scalar[11] = {0,8,8,8,4,4,8,4,4,4,4};
  void *seen[64]; int seen_count=0;
  uint64_t roots_bytes=0, callback_bytes=0, candidate_bytes=0;
  for (int i=0;i<11;i++) {
    assert(!has_pointer(seen, seen_count, roots[i])); seen[seen_count++]=roots[i];
    assert(Moonbit_rc_count(Moonbit_object_header(roots[i])) >= 0);
    roots_bytes += parent_regular_extent(roots[i],scalar[i]);
  }
  const uint32_t *shape=layout(parent); assert(shape[0] == 12 && shape[1] == 6);
  void *callbacks[5];
  for (int i=0;i<5;i++) {
    uint32_t field=i<4?i:5; uint32_t tagged=shape[2+field]; assert(tagged == field*4);
    memcpy(&callbacks[i], (uint8_t*)parent+(tagged>>1)*4, sizeof(void*));
    assert(callbacks[i] && !has_pointer(seen,seen_count,callbacks[i]));
    assert(Moonbit_rc_count(Moonbit_object_header(callbacks[i])) >= 0);
    seen[seen_count++]=callbacks[i];
    callback_bytes += parent_regular_extent(callbacks[i],0);
  }
  // The sixth source field is child_work_issue; reported_work at offset 32
  // owns the initial Result::Ok(Int64) record, separately from five callbacks.
  void *reported; memcpy(&reported,(uint8_t*)parent+32,sizeof reported);
  assert(reported && !has_pointer(seen,seen_count,reported));seen[seen_count++]=reported;
  assert(Moonbit_rc_count(Moonbit_object_header(reported)) >= 0);
  roots_bytes += parent_regular_extent(reported,8);
  void *array; memcpy(&array, children,sizeof array);
  void *buffer; memcpy(&buffer,array,sizeof buffer);
  assert(!has_pointer(seen,seen_count,array)); seen[seen_count++]=array;
  assert(!has_pointer(seen,seen_count,buffer)); seen[seen_count++]=buffer;
  assert(Moonbit_rc_count(Moonbit_object_header(array)) >= 0);
  assert(Moonbit_rc_count(Moonbit_object_header(buffer)) >= 0);
  assert(Moonbit_object_kind(buffer)==moonbit_BLOCK_KIND_REF_ARRAY);
  uint64_t container_bytes=regular_bytes(array)+8+8*(uint64_t)Moonbit_array_length(buffer);
  void *borrowed[6]={sequence,inputs,execution,measurement,numeric,family};
  int candidates=0,embedded=0,matched_environment=0; uint64_t environment_bytes=0;
  for (int i=0;i<5;i++) {
    const uint32_t *s=layout(callbacks[i]);
    for (uint32_t j=0;j<s[1];j++) {
      uint32_t tagged=s[2+j];
      if (tagged&1) { embedded++; continue; }
      void *child; memcpy(&child,(uint8_t*)callbacks[i]+(tagged>>1)*4,sizeof child);
      if (!child || has_pointer(seen,seen_count,child) || has_pointer(borrowed,6,child)) continue;
      assert(seen_count<64); seen[seen_count++]=child;
      // The advance closure's offset-eight capture is the source start_next
      // environment. Bind its actual references, not merely its byte label.
      if (i == 0 && tagged == 4 && Moonbit_object_kind(child)==moonbit_BLOCK_KIND_REGULAR) {
        const uint32_t *env = layout(child);
        assert(Moonbit_rc_count(Moonbit_object_header(child)) >= 0);
        void *expected[12]={used,pending,position,current,previous,children,
          family,numeric,measurement,execution,inputs,sequence};
        uint32_t offsets[12]={0,8,16,24,32,40,48,56,64,80,88,96};
        assert(env[0]==28 && env[1]==12);
        for(int k=0;k<12;k++) {
          assert(env[2+k]==offsets[k]/2);
          void *actual;memcpy(&actual,(uint8_t*)child+offsets[k],sizeof actual);
          assert(actual==expected[k]);
        }
        int32_t captured_count;memcpy(&captured_count,(uint8_t*)child+104,sizeof captured_count);
        assert(captured_count==count && matched_environment==0);
        matched_environment=1;environment_bytes=regular_bytes(child);
      } else {
        candidates++;
        if (Moonbit_object_kind(child)==moonbit_BLOCK_KIND_REGULAR)
          candidate_bytes += parent_regular_extent(child,0);
      }
    }
  }
  char json[2048];
  int n=snprintf(json,sizeof json,"ACTQL_PIPELINE_FAULT:{\"kind\":\"parent control investigation\",\"parent\":\"%" PRIu64 "\",\"count\":%d,\"rootBytes\":%" PRIu64 ",\"callbackBytes\":%" PRIu64 ",\"childrenContainerBytes\":%" PRIu64 ",\"knownOwnedLowerBytes\":%" PRIu64 ",\"unclassifiedCaptures\":%d,\"unclassifiedRegularBytes\":%" PRIu64 ",\"embeddedCaptures\":%d,\"allowance\":%" PRIu64 ",\"matchedEnvironment\":%d,\"environmentBytes\":%" PRIu64 "}",(uint64_t)(uintptr_t)parent,count,roots_bytes,callback_bytes,container_bytes,roots_bytes+callback_bytes+container_bytes,candidates,candidate_bytes,embedded,(uint64_t)count*256,matched_environment,environment_bytes);
  assert(n>0 && (size_t)n<sizeof json);
  moonbit_string_t result=moonbit_make_string_raw(n);
  for (int i=0;i<n;i++) result[i]=(uint16_t)(unsigned char)json[i];
  return result;
}
