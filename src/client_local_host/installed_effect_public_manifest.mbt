///|
// The dependency parser actually normalizes keys. Preserve that constructor's
// complete inventory, plus its owned wire/UTF8 conversion and body carriers.
// Dimensions come from an original immutable wire, not business policy.
pub fn installed_effect_normalized_dependency_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard @execution.execution_capacity(0L, 0L) is Some(empty) &&
    installed_json_effect_response_construction_capacity(
      empty, bytes, nodes, depth,
    )
    is Some(decoded) &&
    @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 6L + nodes.to_int64(),
      scalar_words: 2L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(wire) &&
    @execution.execution_capacity(wire, wire) is Some(encoded) else {
    return None
  }
  @execution.add_execution_capacity(decoded, encoded)
}

///|
// PublicationContract/RunEvidenceValue and CapturedEffectDependencyBody return
// immutable span-free canonical values, original wire and typed edge records.
// Their Source parser/index/NFC controls cannot escape. Keep the COMPLETE old
// construction/failure peak, but only these actual returned families accumulate
// beside later constructors. The row decoder below keeps its separate recipe.
pub fn installed_effect_canonical_body_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard installed_effect_normalized_dependency_capacity(bytes, nodes, depth)
    is Some(peak) &&
    @source.json_tree_retained_construction_extent(
      nodes,
      nodes - 1,
      nodes,
      0,
      bytes.to_int64(),
      keep_spans=false,
    )
    is Some(tree) &&
    @execution.preparation_representation_cost({
      // One body/node/wire/contract wrapper family and at most one typed
      // dependency-reference record per original JSON node. Reference strings
      // borrow the SAME canonical tree; the original wire remains alongside it.
      record_headers: tree.record_headers + 8L + nodes.to_int64(),
      reference_slots: tree.reference_slots + 32L + 4L * nodes.to_int64(),
      scalar_words: tree.scalar_words + 8L,
      owned_utf16_units: tree.owned_utf16_units + bytes.to_int64() + 71L,
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(peak) -
      @execution.execution_capacity_retained_bytes(peak),
      1L,
    )
    is Some(complete) else {
    return None
  }
  @execution.execution_capacity(
    retained,
    Int64::max(complete, @execution.execution_capacity_execution_bytes(peak)),
  )
}

///|
// The measured Artifact subtrees are already admitted. Only the root and
// names use unordered keys, with one growing vector and the two pairing maps.
pub fn installed_effect_public_manifest_inventory(
  count : Int,
  depth : Int,
) -> Int64? {
  if count > 2147483643 {
    return None
  }
  let count64 = count.to_int64()
  guard @shape.collection_construction_extent({
      records: 15L + 4L * count64 + 2L * depth.to_int64(),
      record_references: 20L + 8L * count64 + 2L * depth.to_int64(),
      record_words: 18L + 3L * count64 + 2L * depth.to_int64(),
      reference_arrays: 3L,
      reference_items: 3L * count64 + depth.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 2L * count64,
    })
    is Some(inventory) &&
    @encode.measuring_writer_construction_extent(count + 4, depth)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: inventory.record_headers + writer.record_headers,
    reference_slots: inventory.reference_slots + writer.reference_slots,
    scalar_words: inventory.scalar_words + writer.scalar_words,
    owned_utf16_units: 64L,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn installed_effect_public_manifest_capacity(
  artifacts : Array[@publication.PublicationContract],
  bytes : Int,
  nodes : Int,
  depth : Int,
  max_bytes : Int,
  max_nodes : Int,
  inventory : Int64,
) -> @execution.ExecutionCapacity? {
  // The self-CID key adds one String node and under 100 ASCII bytes.
  // The measured body already includes the original Artifact subtrees.
  let count = artifacts.length()
  // The issuer measures the canonical full object after binding every
  // Artifact exactly once. Its placeholder object keeps those same keys
  // and replaces each already-admitted child with a four-byte null.
  let mut skeleton_bytes = bytes.to_int64()
  for artifact in artifacts {
    guard @publication.publication_contract_name(artifact) == "result_artifact" &&
      @publication.publication_contract_wire_usage(artifact)
      is Some((child, _, _)) &&
      child >= 4 &&
      child.to_int64() <= skeleton_bytes else {
      return None
    }
    skeleton_bytes = skeleton_bytes - child.to_int64() + 4L
  }
  let sealed_bytes = Int64::min(max_bytes.to_int64(), bytes.to_int64() + 100L).to_int()
  let sealed_nodes = Int64::min(max_nodes.to_int64(), nodes.to_int64() + 1L).to_int()
  let skeleton_nodes = Int64::min(
    sealed_nodes.to_int64(),
    count.to_int64() + 6L,
  ).to_int()
  guard installed_effect_canonical_body_capacity(
      skeleton_bytes.to_int(),
      skeleton_nodes,
      Int::min(2, depth),
    )
    is Some(skeleton) &&
    @encode.text_writer_live_key_inventory(sealed_bytes, 0, depth)
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) &&
    @shape.collection_construction_extent({
      // Shape/schema checks over the complete borrowed Artifact tree, plus
      // the patched result/root arrays and the root validator/emit cursors.
      records: 32L + 8L * sealed_nodes.to_int64() + 3L * count.to_int64(),
      record_references: 40L +
      40L * sealed_nodes.to_int64() +
      5L * count.to_int64(),
      record_words: 36L + 32L * sealed_nodes.to_int64() + 3L * count.to_int64(),
      reference_arrays: 9L,
      reference_items: 8L * sealed_nodes.to_int64() + 4L * count.to_int64(),
      scalar_arrays: 1L,
      scalar_items: sealed_nodes.to_int64(),
      maps: 1L,
      map_entries: sealed_nodes.to_int64(),
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: controls.record_headers +
      writer.record_headers +
      hash.record_headers,
      reference_slots: controls.reference_slots +
      writer.reference_slots +
      hash.reference_slots,
      scalar_words: controls.scalar_words +
      writer.scalar_words +
      hash.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(workspace) &&
    @execution.checked_preparation_add_product(inventory, workspace, 1L)
    is Some(workspace) &&
    @execution.preparation_array_representation(2L, 5L + count.to_int64(), true)
    is Some(root_arrays) &&
    @execution.canonical_preparation_retained_bytes(
      {
        nodes: 6L,
        strings: 9L + count.to_int64(),
        text_utf16_units: skeleton_bytes + 100L,
        arrays: 0L,
        objects: 2L,
        array_backing_slots: 0L,
        object_backing_slots: root_arrays.reference_slots,
        max_frame_slots: 0L,
      },
      7L,
      7L,
      5L,
      sealed_bytes.to_int64() + 100L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      workspace,
      @execution.execution_capacity_execution_bytes(skeleton),
      1L,
    )
    is Some(execution) &&
    @execution.checked_preparation_add_product(execution, retained, 1L)
    is Some(peak) else {
    return None
  }
  // Only the new root/skeleton and its final wire are charged on retention.
  // Nested Artifacts remain the original already-backed borrows.
  @execution.execution_capacity(retained, peak)
}
