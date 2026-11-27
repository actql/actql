///|
/// Original semantic Preview, scope and expected bindings kept together until
/// completion. The CID vector is never accepted from a transported Preview.
struct InstalledEffectPreviewDispatchKeys {
  identity : @publication.EffectPreviewIdentity
  scope : @request_scope.LogicalRequestScope
  keys : Array[Array[@effect.EffectDispatchKey]]
  cids : Array[Array[String]]
}

///|
pub fn prepare_installed_effect_preview_dispatch_keys(
  preview : @publication.EffectPreviewIdentity,
  scope : @request_scope.LogicalRequestScope,
) -> Result[InstalledEffectPreviewDispatchKeys, @effect.EffectIdentityIssue] {
  let (bytes, nodes, depth) = @effect.effect_dispatch_key_codec_limits()
  let keys = []
  let cids = []
  for index in 0..<@publication.effect_preview_member_count(preview) {
    guard @publication.effect_preview_row_count(preview, index) is Some(count) else {
      return Err(InvalidRowKey)
    }
    let row_keys = []
    let row_cids = []
    for row in 0..<count {
      let key = match
        @effect.prepare_effect_preview_row_dispatch_key(
          preview, scope, index, row, bytes, nodes, depth,
        ) {
        Ok(key) => key
        Err(issue) => return Err(issue)
      }
      row_keys.push(key)
      row_cids.push(@effect.effect_dispatch_key_cid(key))
    }
    keys.push(row_keys)
    cids.push(row_cids)
  }
  Ok({ identity: preview, scope, keys, cids, })
}

///|
pub fn prepare_installed_effect_preview_dispatch_completion(
  original : @publication.AuthoredEffectPreview,
  dispatch : InstalledEffectPreviewDispatchKeys,
) -> Result[
  @publication.PreparedEffectPreviewDispatch,
  @publication.EffectPreviewIdentityIssue,
] {
  guard physical_equal(
    @publication.authored_effect_preview_identity(original),
    dispatch.identity,
  ) else {
    return Err(PreviewIdentityMismatch)
  }
  @publication.prepare_effect_preview_dispatch_completion(
    original,
    dispatch.cids,
  )
}

///|
pub fn complete_installed_effect_preview_dispatch_wire(
  wire : String,
  dispatch : InstalledEffectPreviewDispatchKeys,
  run : String,
  authoring : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  (String, @publication.EffectPreviewIdentity),
  @publication.EffectPreviewIdentityIssue,
] {
  @publication.complete_effect_preview_dispatch_keys_with_identity(
    wire,
    dispatch.cids,
    run,
    authoring,
    bytes,
    nodes,
    depth,
  )
}

///|
pub fn confirm_installed_effect_preview_dispatch_keys(
  identity : @publication.EffectPreviewIdentity,
  dispatch : InstalledEffectPreviewDispatchKeys,
) -> Result[
  Array[Array[@effect.EffectDispatchKey]],
  @effect.EffectPreviewApplyIdentityIssue,
] {
  @effect.check_admitted_effect_preview_apply_keys(
    identity,
    dispatch.scope,
    dispatch.keys,
  ).map(_ => dispatch.keys)
}

///|
/// Exact vector extents for the original completion workspace. The
/// boundary exposes counts without exposing a writable key or CID vector.
fn installed_effect_preview_dispatch_shape(
  dispatch : InstalledEffectPreviewDispatchKeys,
) -> (Int64, Int64) {
  let members = dispatch.cids.length().to_int64()
  let mut slots = members
  for row_keys in dispatch.cids {
    slots += row_keys.length().to_int64()
  }
  (members, slots)
}

///|
// Original installed UPDATE keys retain their same correlation Strings and one
// newly owned CID each. Both vectors coexist with one bounded key codec;
// the CID-only vector is a temporary input to Preview completion.
pub fn installed_update_effect_preview_dispatch_capacity(
  preview : @publication.EffectPreviewIdentity,
) -> Result[(@execution.ExecutionCapacity, Int64), @effect.EffectIdentityIssue] {
  let (max_key_bytes, max_key_nodes, max_key_depth) = @effect.effect_dispatch_key_codec_limits()
  let members = @publication.effect_preview_member_count(preview)
  let mut rows = 0L
  let mut text = 0L
  let mut largest = 1
  for index in 0..<members {
    guard @publication.effect_preview_member_kind(preview, index) ==
      Some("update") &&
      @publication.effect_preview_row_count(preview, index) is Some(count) else {
      return Err(InvalidRowKey)
    }
    rows += count.to_int64()
    for row in 0..<count {
      guard @publication.effect_preview_row_correlation_wire(
          preview, index, row,
        )
        is Some(correlation) &&
        @scalar.admit_utf8_length(correlation, max_key_bytes) is Ok(bytes) &&
        bytes > 0 else {
        return Err(InvalidRowKey)
      }
      largest = Int::max(largest, bytes)
      text += correlation.length().to_int64()
    }
  }
  let nodes = Int::min(largest, max_key_nodes)
  let depth = Int::min(nodes, max_key_depth)
  let levels = depth.to_int64()
  let arrays = members.to_int64() + 1L
  let slots = members.to_int64() + rows
  // The dispatch wrapper opens one unordered object of four fields.
  // Its canonical correlation uses ordered objects and a growing parent
  // stack, with one cursor and one parent variant per open container.
  let stack = @shape.collection_construction_extent({
    // Keep both completion carriers' control allowance beside the codec.
    records: 9L + 2L * levels,
    record_references: 15L + 2L * levels,
    record_words: 17L + 2L * levels,
    reference_arrays: 1L,
    reference_items: levels,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
  guard @execution.preparation_array_representation(arrays, slots, true)
    is Some(vectors) &&
    @execution.preparation_representation_cost({
      ..vectors,
      record_headers: vectors.record_headers + 3L * rows,
      reference_slots: vectors.reference_slots + 4L * rows,
      owned_utf16_units: text + 71L * rows,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost(vectors)
    is Some(temporary_vectors) &&
    installed_effect_contract_response_construction_capacity(
      largest, nodes, depth,
    )
    is Some(parser) &&
    @encode.hash_writer_live_key_inventory(4, depth + 1) is Some(hash) &&
    stack is Some(stack) &&
    @execution.preparation_representation_cost({
      record_headers: hash.record_headers + stack.record_headers,
      reference_slots: hash.reference_slots + stack.reference_slots,
      scalar_words: hash.scalar_words + stack.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(hash_workspace) &&
    @execution.checked_preparation_add_product(retained, temporary_vectors, 1L)
    .bind(bytes => {
      @execution.checked_preparation_add_product(
        bytes,
        @execution.execution_capacity_execution_bytes(parser),
        1L,
      )
    })
    .bind(bytes => {
      @execution.checked_preparation_add_product(bytes, hash_workspace, 1L)
    })
    .bind(bytes => @execution.execution_capacity(retained, bytes))
    is Some(capacity) else {
    return Err(CapacityExceeded)
  }
  // If the original Compute keeps the group between advances, both vectors
  // and the nominal carrier remain charged after the key codec has returned.
  guard @execution.checked_preparation_add_product(
      retained, temporary_vectors, 1L,
    ).bind(bytes => @execution.checked_preparation_add_product(bytes, 1L, 48L))
    is Some(held) else {
    return Err(CapacityExceeded)
  }
  Ok((capacity, held))
}

///|
// The emission retains the original semantic Preview in its caller. The full
// decode/hash admission quote also covers the preceding emitter: both parse
// one whole wire, and it covers the new wire, key CID vectors and controls.
pub fn installed_effect_preview_completion_capacity(
  usage : (Int, Int, Int),
  keys : InstalledEffectPreviewDispatchKeys,
) -> @execution.ExecutionCapacity? {
  let (bytes, nodes, depth) = usage
  let (members, slots) = installed_effect_preview_dispatch_shape(keys)
  guard @publication.effect_preview_identity_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(admission) &&
    @execution.preparation_array_representation(members + 1L, slots, true)
    is Some(vectors) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: admission.record_headers + vectors.record_headers + 6L,
    reference_slots: admission.reference_slots + vectors.reference_slots + 7L,
    scalar_words: admission.scalar_words + vectors.scalar_words + 9L,
    owned_utf16_units: admission.owned_utf16_units + bytes.to_int64(),
    owned_wire_bytes: admission.owned_wire_bytes,
  }).bind(bytes => @execution.execution_capacity(0L, bytes))
}
