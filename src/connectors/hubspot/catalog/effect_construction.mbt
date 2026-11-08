///|
// Implementation quantities only. Catalog/Mapping, physical buffers and all
// authority stay with their original owners. Shared parser/index, writer and
// collection inventories supply their own representation prices.
fn hubspot_effect_capacity(
  retained : @execution.PreparationRepresentationUnits,
  workspace : Array[@execution.PreparationRepresentationUnits],
) -> @execution.ExecutionCapacity? {
  guard @execution.compose_preparation_representation(workspace)
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Installing one UPDATE driver, its one managed recipe and the original
/// mapping lookup/target predicates. Catalogs, Mappings, limits and Site are
/// borrowed from the same parent. No per-Run requests or authority are owned
/// by this quote. Closed arrays include both initial/maximum quantity vectors,
/// 8 member operations, 15 row operations and 19 Credential selections.
pub fn effect_installation_construction_capacity(
  mappings : Int,
  fields : Int,
  resources : Int,
  text_units : Int,
) -> @execution.ExecutionCapacity? {
  if mappings < 1 || fields < mappings || resources < mappings || text_units < 1 {
    return None
  }
  let m = mappings.to_int64()
  let f = fields.to_int64()
  let r = resources.to_int64()
  // Each captured method has an original receiver/callable pair and closure
  // view. Cover driver/request/observation (96), Plan/extent/response (96),
  // and installing lookup/target/current callbacks (16). Capture vectors and
  // returned records are distinct from those closure views.
  guard @shape.collection_construction_extent({
      records: 2L * (96L + 96L + 16L) + 64L + 5L * m,
      record_references: 14L * (96L + 96L + 16L) + 512L + 24L * m + 2L * f,
      record_words: 128L + 12L * m,
      reference_arrays: 48L + 2L * m,
      reference_items: 512L + 8L + 15L + 19L + 2L * f,
      scalar_arrays: 12L,
      scalar_items: 256L,
      maps: 8L,
      map_entries: m,
    })
    is Some(owned) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      initialization_collection_units(owned),
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        // The Site binding and installation-generation digest escape. Their
        // canonical preimages below are private construction workspace.
        owned_utf16_units: 2L * 71L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) else {
    return None
  }
  hubspot_effect_capacity(retained, [
    {
      // Canonical metadata traverses every declared resource, including
      // those not selected for a write. No second decoded Catalog is made.
      record_headers: 32L + 6L * r + 6L * m,
      reference_slots: 128L + 24L * r + 24L * m,
      scalar_words: 32L + 4L * r + 4L * m,
      owned_utf16_units: text_units.to_int64() * 6L,
      owned_wire_bytes: text_units.to_int64() * 6L,
    },
  ])
}

///|
fn hubspot_effect_body_limits_valid(limits : WriteBodyLimits) -> Bool {
  limits.max_input_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_fields > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0 &&
  limits.max_comparison_work > 0 &&
  limits.max_output_bytes > 0 &&
  limits.max_output_nodes > 0 &&
  limits.max_output_depth > 0
}

///|
/// One original warm UPDATE row and its separate marker finalization, also
/// used by the cold row reconstruction. The same holder retains both logical
/// and marked requests and the once-built target-read request. JSON bodies,
/// typed cell checks, marker-body decoding and writer scratch do not escape.
pub fn effect_request_construction_capacity(
  body : WriteBodyLimits,
  request : RecordRequestLimits,
  read : RecordReadLimits,
  fields : Int,
  field_units : Int,
  binding_units : Int,
) -> @execution.ExecutionCapacity? {
  if !hubspot_effect_body_limits_valid(body) ||
    request.max_rows < 1 ||
    request.max_rows > 100 ||
    request.max_properties < 1 ||
    request.max_trace_bytes < 1 ||
    request.max_body_bytes < 1 ||
    request.max_body_nodes < 1 ||
    request.max_body_depth < 1 ||
    read.max_rows < 1 ||
    read.max_rows > 100 ||
    read.max_properties < 1 ||
    read.max_columns < 1 ||
    read.max_request_bytes < 1 ||
    read.max_request_nodes < 1 ||
    read.max_request_depth < 1 ||
    fields < 1 ||
    fields > body.max_fields ||
    field_units < 1 ||
    binding_units < 1 {
    return None
  }
  let f = fields.to_int64()
  let b = body.max_input_bytes.to_int64()
  let output = body.max_output_bytes.to_int64()
  let batch = request.max_body_bytes.to_int64()
  let read_bytes = read.max_request_bytes.to_int64()
  let units = binding_units.to_int64() + field_units.to_int64()
  // Original value, selector and marked string-property decoders execute
  // sequentially. A complete maximum decoder covers their failure prefixes;
  // the retained body documents above coexist with that private decoder.
  let parse_bytes = Int::max(body.max_input_bytes, request.max_body_bytes)
  let parse_nodes = Int::min(
    parse_bytes,
    Int::max(body.max_nodes, request.max_body_nodes),
  )
  let parse_depth = Int::max(body.max_depth, request.max_body_depth)
  let values = Int::min(parse_bytes, body.max_value_nodes).to_int64()
  guard initialization_decoded_construction(
      parse_bytes, parse_nodes, parse_depth, false,
    )
    is Some(parsed) &&
    initialization_writer_units(
      body.max_output_bytes,
      body.max_output_nodes,
      body.max_output_depth,
    )
    is Some(body_writer) &&
    initialization_writer_units(
      body.max_input_bytes,
      body.max_nodes,
      body.max_depth,
    )
    is Some(marker_writer) &&
    initialization_writer_units(
      request.max_body_bytes,
      request.max_body_nodes,
      request.max_body_depth,
    )
    is Some(batch_writer) &&
    initialization_writer_units(
      read.max_request_bytes,
      read.max_request_nodes,
      read.max_request_depth,
    )
    is Some(read_writer) &&
    @contract.object_construction_inventory(fields, body.max_name_bytes)
    is Some(object) &&
    @contract.checked_emission_construction_extent(fields) is Some(emission) &&
    @shape.collection_construction_extent({
      // Object/field/target lookup Results, cursor alternatives, sorted names,
      // request/marker argument vectors and the active typed-cell comparison.
      // The two checked cell forests have at most V nodes each; their source
      // input and output text are disjoint fields, never F full input copies.
      records: 48L + 20L * f + 4L * values,
      record_references: 96L + 32L * f + 8L * values,
      record_words: 64L + 20L * f + 4L * values,
      reference_arrays: 16L,
      reference_items: 64L + 12L * f + 4L * values,
      scalar_arrays: 4L,
      scalar_items: 4L * b + 4L * values,
      maps: 8L,
      map_entries: 4L * f + values,
    })
    is Some(controls) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  hubspot_effect_capacity(
    {
      // WriteBody, selector, input, logical/marked batches, marker, read request,
      // original Host envelopes, finalization states and method-return records.
      record_headers: 48L,
      reference_slots: 192L + 8L * f,
      scalar_words: 32L,
      // Two body spellings, selector wire/provider value, original batch,
      // logical value/selector wires, read document and logical CID. Installed
      // binding/names are borrowed; finalization owns its new marked document.
      owned_utf16_units: 3L * output + batch + 3L * b + read_bytes + 71L,
      owned_wire_bytes: 0L,
    },
    [
      parsed,
      body_writer,
      body_writer,
      marker_writer,
      batch_writer,
      batch_writer,
      read_writer,
      initialization_collection_units(object.retained),
      initialization_collection_units(object.scratch),
      initialization_collection_units(emission),
      initialization_collection_units(controls),
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        // Full Host canonical logical/physical preimages can be constructed
        // before their later output-bound refusal. Nested strings escape;
        // do not clamp those prefixes to the final recovery wire limit.
        owned_utf16_units: hash.owned_utf16_units +
        object.scratch_utf16_units +
        12L * (b + batch + units) +
        4L * body.max_value_text_bytes.to_int64() +
        4096L,
        owned_wire_bytes: hash.owned_wire_bytes + 2L * b + 2L * batch,
      },
    ],
  )
}

///|
/// Finalization borrows the original logical/native input and read request.
/// Only its marked Batch/Marker/result records, body and physical CID remain.
/// The original request workspace safely covers the narrower marker/encoder
/// prefix, including failure, without retaining or copying that input again.
pub fn effect_finalization_construction_capacity(
  body : WriteBodyLimits,
  request : RecordRequestLimits,
  read : RecordReadLimits,
  fields : Int,
  field_units : Int,
  binding_units : Int,
) -> @execution.ExecutionCapacity? {
  guard effect_request_construction_capacity(
      body, request, read, fields, field_units, binding_units,
    )
    is Some(original) else {
    return None
  }
  guard hubspot_effect_capacity(
      {
        record_headers: 8L,
        reference_slots: 48L,
        scalar_words: 8L,
        owned_utf16_units: request.max_body_bytes.to_int64() + 71L,
        owned_wire_bytes: 0L,
      },
      [],
    )
    is Some(retained) &&
    @execution.add_execution_capacity(
      retained,
      @execution.execution_capacity(
        0L,
        @execution.execution_capacity_execution_bytes(original) -
        @execution.execution_capacity_retained_bytes(original),
      ).unwrap(),
    )
    is Some(result) else {
    return None
  }
  Some(result)
}

///|
/// One complete target response projected into its typed before value and
/// guard. HTTP owns the original body; the first page decoder, envelope
/// decoder, typed cells, timestamp normalization and final writer are private
/// workspace. Only the returned Host row/value graph survives projection.
pub fn effect_target_construction_capacity(
  limits : ObjectPageLimits,
  output : @source.ParseLimits,
  fields : Int,
  field_units : Int,
  binding_units : Int,
) -> @execution.ExecutionCapacity? {
  if !object_page_limits_valid(limits) ||
    limits.max_rows != 1 ||
    output.max_input_bytes < 1 ||
    output.max_nodes < 1 ||
    output.max_depth < 1 ||
    fields < 1 ||
    fields > limits.max_columns ||
    field_units < 1 ||
    binding_units < 1 {
    return None
  }
  let bytes = limits.max_bytes
  let nodes = Int::min(bytes, limits.max_nodes)
  let values = Int::min(bytes, limits.max_value_nodes).to_int64()
  let f = fields.to_int64()
  let output_bytes = Int64::min(
    output.max_input_bytes.to_int64(),
    6L * bytes.to_int64() + 6L * field_units.to_int64() + 64L * f + 1024L,
  )
  let output_nodes = Int64::min(
    output.max_nodes.to_int64(),
    2L * bytes.to_int64() + 4L * f + 16L,
  )
  guard initialization_decoded_construction(
      bytes,
      nodes,
      limits.max_depth,
      false,
    )
    is Some(parsed) &&
    initialization_writer_units(
      output_bytes.to_int(),
      output_nodes.to_int(),
      Int::min(output.max_depth, 6),
    )
    is Some(writer) &&
    @shape.collection_construction_extent({
      // Page/record/cell views, checked values and recheck/selector maps. One
      // row per physical child; malformed wider responses stop before admission.
      records: 64L + 24L * f + 4L * values,
      record_references: 96L + 40L * f + 8L * values,
      record_words: 48L + 24L * f + 4L * values,
      reference_arrays: 12L,
      reference_items: 48L + 8L * f + 4L * values,
      scalar_arrays: 4L,
      scalar_items: 4L * bytes.to_int64(),
      maps: 8L,
      map_entries: 2L * nodes.to_int64() + 4L * f,
    })
    is Some(controls) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  hubspot_effect_capacity(
    {
      record_headers: 8L + output_nodes,
      reference_slots: 16L + 2L * output_nodes,
      scalar_words: 8L + output_nodes,
      owned_utf16_units: output_bytes + field_units.to_int64() + 71L,
      owned_wire_bytes: 0L,
    },
    [
      parsed,
      parsed,
      writer,
      initialization_collection_units(controls),
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        // Page String-array splitting, Decimal/UTC normalized spellings, full
        // canonical row and exact bound guard preimage are not retained JSON ASTs.
        owned_utf16_units: hash.owned_utf16_units +
        4L *
        Int64::min(
          limits.max_value_text_bytes.to_int64(),
          6L * bytes.to_int64() + 64L * f,
        ) +
        8L * output_bytes +
        6L * binding_units.to_int64() +
        1024L,
        owned_wire_bytes: hash.owned_wire_bytes +
        output.max_input_bytes.to_int64(),
      },
    ],
  )
}

///|
/// Native successful acknowledgement plus its small Host outcome. A partial,
/// malformed or non-success response retains its failed original prefix; this
/// quote neither classifies it nor settles a claim.
pub fn effect_response_construction_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  if bytes < 1 || nodes < 1 || depth < 1 {
    return None
  }
  let n = Int::min(bytes, nodes)
  guard initialization_decoded_construction(bytes, n, depth, false)
    is Some(parsed) &&
    @shape.collection_construction_extent({
      records: 48L + 8L * n.to_int64(),
      record_references: 64L + 12L * n.to_int64(),
      record_words: 32L + 8L * n.to_int64(),
      reference_arrays: 8L,
      reference_items: 24L + 4L * n.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 4L,
      map_entries: 2L * n.to_int64(),
    })
    is Some(controls) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  hubspot_effect_capacity(
    {
      record_headers: 8L,
      reference_slots: 16L,
      scalar_words: 4L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    [
      parsed,
      initialization_collection_units(controls),
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        owned_utf16_units: hash.owned_utf16_units + bytes.to_int64(),
        owned_wire_bytes: hash.owned_wire_bytes,
      },
    ],
  )
}

///|
/// Reuse the complete existing initialization peak, but do not retain that
/// parser/sort/schema-export scratch after a successful Account observation.
pub fn effect_account_construction_capacity(
  body_bytes : Int,
  portal_units : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  guard account_initialization_construction_capacity(
      body_bytes, 0, portal_units, max_bytes, max_nodes, max_depth,
    )
    is Some(peak) &&
    hubspot_effect_capacity(
      {
        record_headers: 4L,
        reference_slots: 8L,
        scalar_words: 2L,
        owned_utf16_units: portal_units.to_int64() + 64L,
        owned_wire_bytes: 0L,
      },
      [],
    )
    is Some(retained) &&
    @execution.add_execution_capacity(
      retained,
      @execution.execution_capacity(
        0L,
        @execution.execution_capacity_execution_bytes(peak),
      ).unwrap(),
    )
    is Some(result) else {
    return None
  }
  Some(result)
}

///|
/// ProjectProperties retains only PropertyMetadata, option/name/type Strings,
/// object type and response digest. The complete old bounded constructor peak
/// safely includes its parser/index/sort/contract prefixes, all as workspace.
pub fn effect_metadata_construction_capacity(
  body_bytes : Int,
  object_units : Int,
  limits : PropertyLimits,
) -> @execution.ExecutionCapacity? {
  guard object_initialization_peak_capacity(
      body_bytes,
      0,
      object_units,
      limits,
      limits.max_properties,
      limits.max_name_units,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some((peak, _)) else {
    return None
  }
  guard hubspot_effect_capacity(
      property_catalog_retained_units(body_bytes, object_units, limits),
      [],
    )
    is Some(retained) &&
    @execution.add_execution_capacity(
      retained,
      @execution.execution_capacity(
        0L,
        @execution.execution_capacity_execution_bytes(peak),
      ).unwrap(),
    )
    is Some(result) else {
    return None
  }
  Some(result)
}
