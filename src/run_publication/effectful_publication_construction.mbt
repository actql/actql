///|
fn publication_inventory_add(
  left : EffectPreviewIdentityConstructionInventory,
  right : EffectPreviewIdentityConstructionInventory,
) -> EffectPreviewIdentityConstructionInventory? {
  guard @shape.add_collection_construction_extents(
      {
        record_headers: left.record_headers,
        reference_slots: left.reference_slots,
        scalar_words: left.scalar_words,
      },
      {
        record_headers: right.record_headers,
        reference_slots: right.reference_slots,
        scalar_words: right.scalar_words,
      },
    )
    is Some(control) &&
    right.owned_utf16_units <= 9223372036854775807L - left.owned_utf16_units &&
    right.owned_wire_bytes <= 9223372036854775807L - left.owned_wire_bytes else {
    return None
  }
  Some({
    record_headers: control.record_headers,
    reference_slots: control.reference_slots,
    scalar_words: control.scalar_words,
    owned_utf16_units: left.owned_utf16_units + right.owned_utf16_units,
    owned_wire_bytes: left.owned_wire_bytes + right.owned_wire_bytes,
  })
}

///|
fn publication_inventory_max(
  left : EffectPreviewIdentityConstructionInventory,
  right : EffectPreviewIdentityConstructionInventory,
) -> EffectPreviewIdentityConstructionInventory {
  {
    record_headers: Int64::max(left.record_headers, right.record_headers),
    reference_slots: Int64::max(left.reference_slots, right.reference_slots),
    scalar_words: Int64::max(left.scalar_words, right.scalar_words),
    owned_utf16_units: Int64::max(
      left.owned_utf16_units,
      right.owned_utf16_units,
    ),
    owned_wire_bytes: Int64::max(left.owned_wire_bytes, right.owned_wire_bytes),
  }
}

///|
// Complete typed originals are borrowed by the prepared chain validators.
// Their unchanged protocol checks, array/map copies, canonical stream/text
// comparison and identity hash remain live; no captured JSON is parsed here.
fn publication_borrowed_contract_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard bytes > 0 &&
    nodes > 0 &&
    depth > 0 &&
    protocol_wire_validation_construction_extent(nodes.to_int64())
    is Some(check) &&
    @encode.text_writer_live_key_inventory(bytes, 0, depth) is Some(text) &&
    @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) else {
    return None
  }
  Some(
    (
      {
        record_headers: check.record_headers,
        reference_slots: check.reference_slots,
        scalar_words: check.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: text.record_headers + hash.record_headers,
        reference_slots: text.reference_slots + hash.reference_slots,
        scalar_words: text.scalar_words + hash.scalar_words,
        owned_utf16_units: text.owned_utf16_units +
        hash.owned_utf16_units +
        2L * bytes.to_int64(),
        owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
      },
    ),
  )
}

///|
// The same finite Receipt/Source artifact codec is used for the constructor
// and its later Store adoption. Canonical emitters are ordered: none of their
// payload keys are simultaneously retained unordered writer entries.
fn publication_adoption_inventory(
  wire : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  guard review_original_wire_geometry(wire, bytes, nodes, depth)
    is Some(geometry) else {
    return None
  }
  protocol_wire_codec_construction_inventory(
    bytes,
    nodes,
    depth,
    geometry=Some(geometry),
    live_keys=Some(0),
  )
}

///|
// One escaping immutable contract: canonical backing, complete wire and its
// decoded text, measured-usage Some/tuple, Host view/bounds, and two existing
// WeakMap entries. A returned contract retains no Source parser or visit map.
fn publication_returned_contract_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
  geometry? : @encode.EncodingConstructionGeometry? = None,
) -> EffectPreviewIdentityConstructionInventory? {
  guard @json.source_conversion_construction_extent(
      nodes,
      geometry.map(v => v.fields).unwrap_or(nodes),
      geometry.map(v => v.objects).unwrap_or(nodes),
      geometry.map(v => v.arrays).unwrap_or(nodes),
      depth,
      0,
    )
    is Some(canonical) &&
    @shape.collection_construction_extent({
      records: 7L,
      record_references: 11L,
      record_words: 7L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 2L,
    })
    is Some(contract) else {
    return None
  }
  Some({
    record_headers: canonical.retained.record_headers + contract.record_headers,
    reference_slots: canonical.retained.reference_slots +
    contract.reference_slots,
    scalar_words: canonical.retained.scalar_words + contract.scalar_words,
    owned_utf16_units: 2L * bytes.to_int64() + 71L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Depth-bounded measurement on the same immutable canonical values. This
/// writer constructs no text, parser, canonical forest, hash or semantic proof.
/// The caller reserves this scratch before invoking any subtree census.
pub fn effectful_publication_measurement_construction_inventory(
  depth : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  if depth < 1 {
    return None
  }
  let d = depth.to_int64()
  let operation = @encode.measurement_operation_construction_extent()
  guard @encode.measuring_writer_construction_extent(0, depth) is Some(writer) &&
    @shape.collection_construction_extent({
      // SyncEmitParent and its cursor per open container, the current popped
      // parent/next cursor and the original growing parent stack.
      records: 4L + 2L * d,
      record_references: 8L + 2L * d,
      record_words: 6L + 2L * d,
      reference_arrays: 1L,
      reference_items: d,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(emit) else {
    return None
  }
  Some({
    record_headers: writer.record_headers +
    emit.record_headers +
    operation.collections.record_headers +
    4L,
    reference_slots: writer.reference_slots +
    emit.reference_slots +
    operation.collections.reference_slots +
    3L,
    scalar_words: writer.scalar_words +
    emit.scalar_words +
    operation.collections.scalar_words +
    18L,
    owned_utf16_units: operation.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn publication_canonical_construction_geometry(
  value : @json.CanonicalValue,
  bytes : Int,
  nodes : Int,
  depth : Int,
  work? : ((Int) -> Bool)? = None,
) -> @encode.EncodingConstructionGeometry? {
  try {
    let writer = match work {
      None => @encode.construction_measuring_writer(bytes, nodes, depth)
      Some(spend) =>
        @encode.work_construction_measuring_writer(bytes, nodes, depth, spend)
    }
    @json.emit_value(value, writer)
    Some(@encode.finish_construction_measurement(writer))
  } catch {
    _ => None
  }
}

///|
/// Constructor DATA for the exact prepared final-publication methods. Original
/// contracts remain with the completed Read. Returned inventories additionally
/// keep the newly issued/admitted Receipt and Host adoption envelopes alive
/// across publication awaits; they confer no chain validity or Store authority.
/// The caller prepays the sequential geometry cursor and metadata arrays.
pub fn effectful_publication_construction_inventory(
  issue : Bool,
  contracts : Array[PublicationContract],
  receipt_wires : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  prepared? : PreparedCapturedEffectRun? = None,
  work? : ((Int) -> Bool)? = None,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  if contracts.length() < 2 ||
    receipt_wires.length() < 1 ||
    max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    contracts[0].name != "captured_run" ||
    contracts[1].name != "run_receipt" {
    return None
  }
  let zero : EffectPreviewIdentityConstructionInventory = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut borrowed = zero
  let mut checks = zero
  let mut returned = zero
  let mut codecs = zero
  let mut adoption = zero
  for contract in contracts {
    guard contract.wire_usage is Some((bytes, nodes, depth)) else {
      return None
    }
    let pair = match prepared {
      Some(original) if physical_equal(contract, contracts[0]) &&
        physical_equal(contract, original.captured) =>
        match
          publication_prepared_capture_borrowed_inventory(
            contract,
            original,
            Int::max(max_bytes, original.max_bytes),
            Int::max(max_nodes, original.max_nodes),
            Int::max(max_depth, original.max_depth),
            work~,
          ) {
          Some(value) => Some(value)
          // In particular a declined Work view must end this census now;
          // generic fallback cannot continue inspecting later bodies.
          None => return None
        }
      _ => publication_borrowed_contract_inventory(bytes, nodes, depth)
    }
    guard pair is Some((control, value)) &&
      publication_inventory_add(checks, control) is Some(next_checks) else {
      return None
    }
    // These validators visit one nominal contract at a time. Preserve every
    // backing of the original separately; this MAX concerns only scratch.
    borrowed = publication_inventory_max(borrowed, value)
    // Cross-contract name/reference maps can survive the next stream visit.
    // Preserve their total; only sequential stream/text/hash writers use MAX.
    checks = next_checks
    if issue && contract.name == "effect_source_artifact" {
      guard publication_adoption_inventory(contract.wire, bytes, nodes, depth)
        is Some(value) &&
        review_original_wire_geometry(contract.wire, bytes, nodes, depth)
        is Some(geometry) &&
        publication_returned_contract_inventory(
          bytes,
          nodes,
          depth,
          geometry=Some(geometry),
        )
        is Some(output) &&
        publication_inventory_add(returned, output) is Some(next) else {
        return None
      }
      returned = next
      guard publication_inventory_add(codecs, value) is Some(next) else {
        return None
      }
      codecs = next
      // The detached JSON.parse forest is temporary; only its schema CID
      // survives in the Host array. Keep its actual class in the sequential
      // post-return adoption envelope, not once per permanent output.
      guard @source.json_tree_retained_construction_extent(
          nodes,
          geometry.fields,
          geometry.objects,
          geometry.arrays,
          bytes.to_int64(),
          keep_spans=false,
        )
        is Some(host) &&
        publication_inventory_add(value, {
          record_headers: host.record_headers,
          reference_slots: host.reference_slots,
          scalar_words: host.scalar_words,
          owned_utf16_units: bytes.to_int64(),
          owned_wire_bytes: 0L,
        })
        is Some(packet) else {
        return None
      }
      adoption = publication_inventory_max(adoption, packet)
    }
  }
  for wire in receipt_wires {
    guard review_original_wire_geometry(wire, max_bytes, max_nodes, max_depth)
      is Some(geometry) &&
      publication_adoption_inventory(
        wire,
        geometry.bytes,
        geometry.nodes,
        geometry.depth,
      )
      is Some(value) &&
      publication_inventory_add(codecs, value) is Some(next) else {
      return None
    }
    codecs = next
    if issue {
      // First admission survives through publishRun; the Store then admits
      // the same Set/member wire again while the first views remain held.
      guard publication_returned_contract_inventory(
          geometry.bytes,
          geometry.nodes,
          geometry.depth,
          geometry=Some(geometry),
        )
        is Some(output) &&
        publication_inventory_add(returned, output) is Some(next) &&
        publication_inventory_add(next, output) is Some(next) else {
        return None
      }
      returned = next
      adoption = publication_inventory_max(adoption, value)
    }
  }
  if issue {
    guard contracts[1].wire_usage is Some((bytes, nodes, depth)) &&
      bytes <= 2147483647 - 293 &&
      nodes <= 2147483647 - 3 &&
      protocol_wire_codec_construction_inventory(
        bytes + 293,
        nodes + 3,
        depth,
        live_keys=Some(0),
      )
      is Some(final_codec) &&
      publication_returned_contract_inventory(bytes + 293, nodes + 3, depth)
      is Some(output) &&
      publication_inventory_add(returned, output) is Some(next) &&
      publication_inventory_add(next, output) is Some(next) &&
      publication_inventory_add(codecs, final_codec) is Some(peak) else {
      return None
    }
    returned = next
    codecs = peak
    adoption = publication_inventory_max(adoption, final_codec)
  }
  // Host contract/bounds/token views, receipt/evidence/preparation carriers,
  // source-schema strings and their actual Array growth remain through the
  // Store awaits. Reference contents borrow their independently owned wires.
  let count = contracts.length().to_int64() +
    receipt_wires.length().to_int64() +
    1L
  guard @shape.collection_construction_extent({
      records: 12L + 8L * count,
      record_references: 48L + 18L * count,
      record_words: 12L + 8L * count,
      reference_arrays: 8L,
      reference_items: 4L * count,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: count,
    })
    is Some(host) else {
    return None
  }
  if issue {
    guard publication_inventory_add(returned, adoption)
      is Some(returned_with_adoption) &&
      publication_inventory_add(returned_with_adoption, {
        record_headers: host.record_headers,
        reference_slots: host.reference_slots,
        scalar_words: host.scalar_words,
        owned_utf16_units: 71L * count,
        owned_wire_bytes: 0L,
      })
      is Some(next) else {
      return None
    }
    returned = next
  }
  // The first Set and newly issued Final can coexist with the subsequent full
  // reference check. Keep two codec packets alongside the borrowed chain.
  guard publication_inventory_add(codecs, codecs) is Some(codecs) &&
    publication_inventory_add(borrowed, checks) is Some(borrowed) &&
    publication_inventory_add(borrowed, codecs) is Some(peak) else {
    return None
  }
  Some((returned, peak))
}

///|
/// One in-guest issuer borrows the retained checked computation. It admits
/// one Set/member closure and writes one final Receipt. The caller retains
/// the already issued Set and member wires and prepays this geometry cursor.
pub fn retained_effectful_final_issuance_inventory(
  computation : RetainedEffectfulComputation,
  set_wire : String,
  member_wires : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  let original = computation.inputs
  guard original.preview is Some(preview) &&
    member_wires.length() == effect_preview_member_count(preview) &&
    original.receipt.wire_usage is Some((bytes, nodes, depth)) &&
    max_bytes >= 293 && bytes <= max_bytes - 293 &&
    max_nodes >= 3 && nodes <= max_nodes - 3 &&
    depth <= max_depth &&
    protocol_wire_codec_construction_inventory(
      bytes + 293, nodes + 3, depth, live_keys=Some(0),
    ) is Some(final_codec) &&
    publication_returned_contract_inventory(bytes + 293, nodes + 3, depth)
      is Some(final_backing) else {
    return None
  }
  let controls = 1L + member_wires.length().to_int64() +
    original.definitions.length().to_int64()
  guard @shape.collection_construction_extent({
      records: 24L + 4L * controls,
      record_references: 62L + 12L * controls,
      record_words: 32L + 8L * controls,
      reference_arrays: 12L,
      reference_items: 12L * controls,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 4L,
      map_entries: 4L * controls,
    }) is Some(control) else { return None }
  let mut retained : EffectPreviewIdentityConstructionInventory = {
    record_headers: control.record_headers,
    reference_slots: control.reference_slots,
    scalar_words: control.scalar_words,
    owned_utf16_units: 71L * controls,
    owned_wire_bytes: 0L,
  }
  let mut scratch = final_codec
  for index in 0..=member_wires.length() {
    let wire = if index == member_wires.length() { set_wire } else { member_wires[index] }
    guard review_original_wire_geometry(wire, max_bytes, max_nodes, max_depth)
      is Some(geometry) &&
      protocol_wire_codec_construction_inventory(
        geometry.bytes, geometry.nodes, geometry.depth,
        geometry=Some(geometry), live_keys=Some(0),
      ) is Some(codec) &&
      publication_returned_contract_inventory(
        geometry.bytes, geometry.nodes, geometry.depth, geometry=Some(geometry),
      ) is Some(backing) &&
      publication_inventory_add(retained, backing) is Some(next) else {
      return None
    }
    retained = next
    scratch = publication_inventory_max(scratch, codec)
  }
  // Typed admitted member views and the Set closure can coexist with the
  // final constructor. Only one raw input is parsed at a time.
  publication_inventory_add(retained, final_backing)
    .bind(value => publication_inventory_add(value, scratch))
}
