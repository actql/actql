/* Proof-only reader for the pinned native ABI. No allocation, reference-count
 * changes, stored object pointers or traversal after the borrowed call ends. */
#include "moonbit.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <stdio.h>

extern const uint32_t *moonbit_layout_table;

static const uint32_t *layout(void *object) {
  assert(object && moonbit_layout_table);
  struct moonbit_object *header = Moonbit_object_header(object);
  assert(Moonbit_object_kind(object) == moonbit_BLOCK_KIND_REGULAR);
  assert((header->meta >> MOONBIT_REGULAR_LAYOUT_CLASS_SHIFT) ==
         MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED);
  uint32_t index = (header->meta >> MOONBIT_REGULAR_LAYOUT_INDEX_SHIFT) &
                   MOONBIT_REGULAR_LAYOUT_INDEX_MASK;
  return &moonbit_layout_table[index];
}

static uint64_t regular_bytes(void *object) {
  return sizeof(struct moonbit_object) + (uint64_t)layout(object)[0] * 4;
}

static void *map_table(void *map) {
  const uint32_t *shape = layout(map);
  assert(shape[1] == 2);
  assert(shape[0] == 10 && shape[2] == 0 && shape[3] == 12);
  void *table = NULL;
  for (uint32_t i = 0; i < shape[1]; i++) {
    uint32_t field = shape[2 + i];
    assert((field & 1) == 0); /* No embedded value-enum field. */
    uint64_t offset = (uint64_t)(field >> 1) * 4;
    assert(offset + sizeof(void *) <= (uint64_t)shape[0] * 4);
    void *child;
    memcpy(&child, (uint8_t *)map + offset, sizeof child);
    if (child && Moonbit_object_kind(child) == moonbit_BLOCK_KIND_REF_ARRAY) {
      assert(table == NULL);
      table = child;
    }
  }
  assert(table);
  return table;
}

/* The selector exposes scalar facts only. Size is the compiler/runtime's
 * requested object extent, not malloc arena size or process-memory usage. */
uint64_t actql_proof_map_layout(void *map, int32_t selector) {
  void *table = map_table(map);
  int32_t slots = Moonbit_array_length(table);
  assert(slots == 8 || slots == 16);
  uint64_t entries = 0, entry_bytes = 0;
  void *seen[16];
  for (int32_t i = 0; i < slots; i++) {
    void *entry;
    memcpy(&entry, (uint8_t *)table + (size_t)i * sizeof(void *), sizeof entry);
    if (!entry) continue;
    for (uint64_t j = 0; j < entries; j++) assert(seen[j] != entry);
    seen[entries++] = entry;
    const uint32_t *entry_shape = layout(entry);
    assert(entry_shape[0] == 10 && entry_shape[1] == 2 &&
           entry_shape[2] == 4 && entry_shape[3] == 12);
    entry_bytes += regular_bytes(entry);
  }
  switch (selector) {
    case 0: return regular_bytes(map);
    case 1: return (uint64_t)(uintptr_t)table;
    case 2: return (uint64_t)slots;
    case 3: return sizeof(struct moonbit_object) + (uint64_t)slots * sizeof(void *);
    case 4: return entries;
    case 5: return entry_bytes;
    case 6: return regular_bytes(map) + sizeof(struct moonbit_object) +
                   (uint64_t)slots * sizeof(void *) + entry_bytes;
    case 7: return sizeof(struct moonbit_object);
    case 8: return sizeof(void *);
    case 9: return (uint64_t)(uintptr_t)map;
    default: assert(0); return 0;
  }
}

/* Formatting allocation belongs to the observer, not the measured Map leaves.
 * Every Map argument is borrowed; only numeric identity/extent facts escape. */
moonbit_string_t actql_proof_map_json(void *input, void *binding,
                                    void *projection, void *snapshot) {
  void *maps[4] = {input, binding, projection, snapshot};
  const char *names[4] = {"inputOrdinals", "bindingOrdinals", "projectionOrdinals", "snapshot"};
  char buffer[2048];
  size_t used = (size_t)snprintf(buffer, sizeof buffer, ",\"nativeMaps\":{");
  for (int i = 0; i < 4; i++) {
    int written = snprintf(buffer + used, sizeof buffer - used,
      "%s\"%s\":{\"owner\":\"%" PRIu64 "\",\"table\":\"%" PRIu64
      "\",\"slots\":%" PRIu64 ",\"entries\":%" PRIu64
      ",\"requestedBytes\":\"%" PRIu64 "\"}",
      i ? "," : "", names[i], actql_proof_map_layout(maps[i], 9),
      actql_proof_map_layout(maps[i], 1), actql_proof_map_layout(maps[i], 2),
      actql_proof_map_layout(maps[i], 4), actql_proof_map_layout(maps[i], 6));
    assert(written > 0 && (size_t)written < sizeof buffer - used);
    used += (size_t)written;
  }
  assert(used + 1 < sizeof buffer);
  buffer[used++] = '}';
  moonbit_string_t result = moonbit_make_string_raw((int32_t)used);
  for (size_t i = 0; i < used; i++) result[i] = (uint16_t)(unsigned char)buffer[i];
  return result;
}
