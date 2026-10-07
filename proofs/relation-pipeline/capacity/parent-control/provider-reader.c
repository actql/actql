/* Borrowed constructor census only. Identity set lives on this C stack; no
 * MoonBit pointer is stored, retained or returned to a later observer. */
moonbit_string_t actql_proof_provider_construction(void *candidates,
  void *execution, void *measurement) {
  void *seen[128]; int seen_count = 0;
  void *queue[128]; int queued = 0, cursor = 0;
  void *records[11];
  void *scalar_objects[44]; intptr_t scalar_deltas[44];
  assert(Moonbit_object_kind(candidates) == moonbit_BLOCK_KIND_REGULAR);
  const uint32_t *a = layout(candidates);
  assert(a[0] == 4 && a[1] == 1 && a[2] == 0);
  void *backing; memcpy(&backing, candidates, sizeof backing);
  assert(Moonbit_object_kind(backing) == moonbit_BLOCK_KIND_REF_ARRAY);
  int32_t length; memcpy(&length, (uint8_t *)candidates + 8, sizeof length);
  assert(length == 11 && Moonbit_array_length(backing) == 11);
  assert(Moonbit_rc_count(Moonbit_object_header(candidates)) >= 0);
  assert(Moonbit_rc_count(Moonbit_object_header(backing)) >= 0);
  seen[seen_count++] = candidates; seen[seen_count++] = backing;
  uint64_t bytes = regular_bytes(candidates) + 8 + 11 * 8;
  int callbacks = 0, arrays = 0, unclassified = 0, scalar = 0;
  for (int i = 0; i < 11; i++) {
    memcpy(&records[i], (uint8_t *)backing + i * 8, sizeof(void *));
    assert(records[i] && !has_pointer(seen, seen_count, records[i]));
    seen[seen_count++] = records[i];
    assert(Moonbit_rc_count(Moonbit_object_header(records[i])) >= 0);
    const uint32_t *s = layout(records[i]);
    assert(s[0] == 8 && s[1] == 4);
    bytes += regular_bytes(records[i]);
    for (int j = 0; j < 4; j++) {
      assert(s[2 + j] == (uint32_t)j * 4);
      void *callback; memcpy(&callback, (uint8_t *)records[i] + j * 8, sizeof callback);
      if (callback) { assert(queued < 128); queue[queued++] = callback; }
    }
  }
  while (cursor < queued) {
    void *object = queue[cursor++];
    if (object == execution || object == measurement ||
        has_pointer(seen, seen_count, object)) continue;
    /* Static functions/backings are existing runtime objects, not new
     * constructor allocations. Dynamic noncapturing functions require
     * a separate scalar allocation-size premise. Record their count without
     * inventing an extent from the scalar descriptor. The admission boundary
     * keeps complete constructor-byte correspondence explicitly unresolved. */
    if (Moonbit_rc_count(Moonbit_object_header(object)) < 0) continue;
    assert(seen_count < 128); seen[seen_count++] = object;
    if (Moonbit_object_kind(object) != moonbit_BLOCK_KIND_REGULAR) {
      unclassified++; continue;
    }
    struct moonbit_object *header = Moonbit_object_header(object);
    uint32_t cls = header->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT;
    if (cls == MOONBIT_REGULAR_LAYOUT_CLASS_SCALAR) {
      /* This is code identity, not a descriptor-derived payload size. The
       * independent generated-code consumer establishes allocation requests. */
      uintptr_t code; memcpy(&code, object, sizeof code);
      assert(scalar < 44);
      scalar_objects[scalar] = object;
      scalar_deltas[scalar] = (intptr_t)code - (intptr_t)&actql_proof_provider_construction;
      scalar++; continue;
    }
    const uint32_t *s = layout(object);
    /* The sole source-owned default family Array has a ref at zero and
     * an Int length at eight. A callback's offset zero is its code pointer,
     * so its capture references start at eight. */
    if (s[0] == 4 && s[1] == 1 && s[2] == 0) {
      void *empty; memcpy(&empty, object, sizeof empty);
      int32_t count; memcpy(&count, (uint8_t *)object + 8, sizeof count);
      assert(count == 0 && Moonbit_array_length(empty) == 0);
      assert(Moonbit_rc_count(Moonbit_object_header(empty)) < 0);
      arrays++; bytes += regular_bytes(object); continue;
    }
    assert(s[1] <= 3 && regular_bytes(object) <= 40);
    callbacks++; bytes += regular_bytes(object);
    for (uint32_t j = 0; j < s[1]; j++) {
      uint32_t tagged = s[2 + j];
      assert(!(tagged & 1) && tagged >= 4 && tagged <= 12);
      void *capture; memcpy(&capture, (uint8_t *)object + (tagged >> 1) * 4, sizeof capture);
      if (capture) { assert(queued < 128); queue[queued++] = capture; }
    }
  }
  struct current_json json = {.used = 0};
  current_add(&json,
    "ACTQL_PIPELINE_FAULT:{\"kind\":\"provider construction observation\",\"providers\":11,\"records\":11,\"arraySlots\":11,\"callbacks\":%d,\"defaultArrays\":%d,\"indexedBytes\":%" PRIu64 ",\"unclassifiedCaptures\":%d,\"scalarDynamicCallbacks\":%d,\"scalarCodes\":[",
    callbacks, arrays, bytes, unclassified, scalar);
  for (int i = 0; i < scalar; i++) {
    current_add(&json, "%s{\"identity\":\"%" PRIxPTR "\",\"codeDelta\":\"%" PRIdPTR "\"}",
      i ? "," : "", (uintptr_t)scalar_objects[i], scalar_deltas[i]);
  }
  current_add(&json, "]}");
  return current_string(&json);
}
