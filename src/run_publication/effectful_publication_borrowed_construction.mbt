///|
fn publication_borrowed_collection_inventory(
  inventory : @shape.CollectionConstructionInventory,
  text_units : Int64,
) -> EffectPreviewIdentityConstructionInventory? {
  guard text_units >= 0 &&
    @shape.collection_construction_extent(inventory) is Some(value) else {
    return None
  }
  Some({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: text_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn publication_borrowed_object_count(
  value : @json.CanonicalValue,
  name : String,
) -> Int? {
  guard @json.object_field(value, name) is Some(child) else { return None }
  @json.object_field_count(child)
}

///|
// Only the exact completed capture can select this prepared validator class.
// It prices live collections, not the 4096+8N continuation budget or a full
// generated protocol visitor which the prepared branch never constructs.
fn publication_prepared_capture_borrowed_inventory(
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work? : ((Int) -> Bool)? = None,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard physical_equal(captured, prepared.captured) &&
    captured.name == "captured_run" &&
    captured.wire_usage is Some((bytes, nodes, depth)) &&
    max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    publication_borrowed_contract_inventory(bytes, nodes, depth)
    is Some((_, writer)) &&
    publication_canonical_construction_geometry(
      captured.value,
      bytes,
      nodes,
      depth,
      work~,
    )
    is Some(geometry) &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(captured.value, "receipt") is Some(receipt) &&
    publication_borrowed_object_count(context, "effects") is Some(effects) &&
    publication_borrowed_object_count(context, "effect_source_artifacts")
    is Some(artifacts) &&
    publication_borrowed_object_count(context, "effect_source_holding_cids")
    is Some(holdings) &&
    publication_borrowed_object_count(context, "effect_source_local_inventory")
    is Some(sources) &&
    publication_borrowed_object_count(context, "effect_plans") is Some(plans) &&
    publication_borrowed_object_count(context, "effect_plan_logical_cids")
    is Some(plan_cids) &&
    @json.object_field(context, "effect_source_local_inventory")
    is Some(@json.Object(local_sources)) &&
    @json.object_field(context, "result_fields")
    is Some(@json.Object(result_fields)) &&
    @json.object_field(context, "model_invocation_evidence")
    is Some(@json.Array(models)) &&
    @json.object_field(receipt, "external_observation_evidence")
    is Some(@json.Array(external)) else {
    return None
  }

  // Two genuine prepared-root maps survive an artifact wire comparison.
  // object_fields in the caller and root matcher keep two detached source
  // arrays. Observation/relation arrays borrow their original Strings.
  let roots = prepared.inventory.roots.length().to_int64()
  let mut key_units = 0L
  let mut prefix_units = 0L
  let mut key_count = roots
  for root in prepared.inventory.roots {
    match work {
      Some(consume) => if !consume(1) { return None }
      None => ()
    }
    let prefix = root.node.kind.length().to_int64() + 1L
    let units = prefix + root.node.identity.length().to_int64()
    if units > 9223372036854775807L - key_units {
      return None
    }
    key_units += units
    prefix_units = Int64::max(prefix_units, prefix)
  }
  let mut source_refs = 0L
  for index in 0..<@json.array_count(local_sources) {
    match work {
      Some(consume) => if !consume(1) { return None }
      None => ()
    }
    let source = @json.array_at(local_sources, index).unwrap().1
    guard @json.object_field(source, "invocation") is Some(invocation) &&
      @json.object_field(invocation, "observation_cids")
      is Some(@json.Array(observations)) &&
      @json.object_field(source, "derivation") is Some(derivation) &&
      @json.object_field(derivation, "input_relation_cids")
      is Some(@json.Array(relations)) else {
      return None
    }
    let observation_count = @json.array_count(observations).to_int64()
    let relation_count = @json.array_count(relations).to_int64()
    let refs = observation_count + relation_count
    // evidence_string_array also detaches the FrozenArray before copying
    // its String references. Only one such temporary input is live at once.
    source_refs = Int64::max(
      source_refs,
      refs + Int64::max(observation_count, relation_count),
    )
    if refs > 0L {
      guard @json.object_field(source, "artifact") is Some(artifact) &&
        @json.object_field(source, "definition") is Some(definition) &&
        evidence_string(artifact, "result_artifact_cid") is Some(identity) else {
        return None
      }
      let prefix = match evidence_string(definition, "version") {
        Some("actql-local-result-definition/0.1") =>
          "result_artifact".length().to_int64() + 1L
        Some("actql-local-table-input-definition/0.1") =>
          "table_input_artifact".length().to_int64() + 1L
        _ => return None
      }
      let units = prefix + identity.length().to_int64()
      if units > 9223372036854775807L - key_units {
        return None
      }
      key_units += units
      key_count += 1L
      prefix_units = Int64::max(prefix_units, prefix)
    }
  }
  if prefix_units > 9223372036854775807L - key_units {
    return None
  }

  // One Result is checked at a time. The parent's cleared fields array can
  // retain its maximum backing through later phases. The child additionally
  // owns fields, singleton sort keys and the sort's two scalar index arrays.
  let mut fields = 0L
  let mut field_units = 0
  for index in 0..<@json.array_count(result_fields) {
    match work {
      Some(consume) => if !consume(1) { return None }
      None => ()
    }
    guard @json.array_at(result_fields, index).unwrap().1 is @json.Array(names) else {
      return None
    }
    fields = Int64::max(fields, @json.array_count(names).to_int64())
    for column in 0..<@json.array_count(names) {
      match work {
        Some(consume) => if !consume(1) { return None }
        None => ()
      }
      guard @json.array_at(names, column) is Some(@json.String(name)) else {
        return None
      }
      field_units = Int::max(field_units, name.length())
    }
  }
  let model_count = @json.array_count(models).to_int64()
  let mut external_models = 0L
  for index in 0..<@json.array_count(external) {
    match work {
      Some(consume) => if !consume(1) { return None }
      None => ()
    }
    let value = @json.array_at(external, index).unwrap()
    guard evidence_string(value, "kind") is Some(kind) else { return None }
    if kind == "model_invocation" {
      external_models += 1L
    }
  }

  guard publication_local_source_construction_inventory(
      context,
      Int::max(max_bytes, prepared.max_bytes),
      Int::max(max_nodes, prepared.max_nodes),
      Int::max(max_depth, prepared.max_depth),
      work~,
    )
    is Some(local_source) &&
    publication_prepared_capture_phase_inventory(
      depth,
      geometry.largest_object,
      roots,
      key_units,
      prefix_units,
      key_count,
      source_refs,
      effects,
      artifacts,
      holdings,
      sources,
      plans,
      plan_cids,
      fields,
      field_units,
      model_count,
      external_models,
      local_source,
    )
    is Some(checks) else {
    return None
  }
  Some((checks, writer))
}

///|
// Owner-local numeric census recipe. The actual context reader and focused
// quantity checks share these collection/lifetime formulas. It grants no
// validity and retains no census token or object beside the original capture.
fn publication_prepared_capture_phase_inventory(
  depth : Int,
  largest_object : Int,
  roots : Int64,
  key_units : Int64,
  prefix_units : Int64,
  key_count : Int64,
  source_refs : Int64,
  effects : Int,
  artifacts : Int,
  holdings : Int,
  sources : Int,
  plans : Int,
  plan_cids : Int,
  fields : Int64,
  field_units : Int,
  model_count : Int64,
  external_models : Int64,
  local_source : EffectPreviewIdentityConstructionInventory,
) -> EffectPreviewIdentityConstructionInventory? {
  if depth < 1 ||
    largest_object < 0 ||
    roots < 0L ||
    key_units < 0L ||
    prefix_units < 0L ||
    key_count < 0L ||
    source_refs < 0L ||
    effects < 0 ||
    artifacts < 0 ||
    holdings < 0 ||
    sources < 0 ||
    plans < 0 ||
    plan_cids < 0 ||
    fields < 0L ||
    fields > 2147483647L ||
    field_units < 0 ||
    model_count < 0L ||
    model_count > 2147483647L ||
    external_models < 0L ||
    external_models > 2147483647L ||
    roots > 2147483647L ||
    key_count > 4294967294L ||
    source_refs > 6442450941L ||
    prefix_units > 9223372036854775807L - key_units {
    return None
  }
  let d = depth.to_int64()
  // Fixed inputs/check/prelude, one active child/stream, two suffix Sorts,
  // Some/Result and old/current phase carriers are co-counted. These controls
  // do not grow with node visits. Two canonical streams need at most D+1
  // pending frames each, plus the popped frame during advance and D cursors;
  // their arrays retain actual growth backing. The ordered writer packet
  // below separately owns writer frames, text/hash state and bounded chunks.
  // One largest-object root copy covers context/proof/model CID preimages or
  // the sequential detached fields in evidence_inventory_names.
  guard publication_borrowed_collection_inventory(
      {
        records: 64L + 6L * (d + 2L),
        record_references: 192L + 10L * (d + 2L),
        record_words: 192L + 4L * (d + 2L),
        reference_arrays: 5L,
        reference_items: 2L * (d + 2L) +
        largest_object.to_int64() +
        fields +
        external_models,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      },
      0L,
    )
    is Some(common) &&
    publication_borrowed_collection_inventory(
      {
        records: key_count + 1L,
        record_references: 0L,
        record_words: 0L,
        reference_arrays: 5L,
        reference_items: 2L * sources.to_int64() + source_refs,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 2L,
        map_entries: roots + Int64::min(roots, sources.to_int64()),
      },
      key_units + prefix_units,
    )
    is Some(dependencies) &&
    publication_borrowed_collection_inventory(
      {
        records: 0L,
        record_references: 0L,
        record_words: 0L,
        reference_arrays: 8L,
        // The first same_names length check proves Preview M == effects E
        // before either member-subset array is populated. Failed prefixes
        // still keep all already-created inventories at their actual widths.
        reference_items: 3L * effects.to_int64() +
        artifacts.to_int64() +
        holdings.to_int64() +
        sources.to_int64() +
        plans.to_int64() +
        plan_cids.to_int64(),
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      },
      0L,
    )
    is Some(names) &&
    publication_inventory_add(names, local_source) is Some(names) &&
    publication_borrowed_collection_inventory(
      {
        records: 0L,
        record_references: 0L,
        record_words: 0L,
        reference_arrays: fields + 2L,
        reference_items: 3L * fields,
        scalar_arrays: 2L,
        scalar_items: 2L * fields,
        maps: 0L,
        map_entries: 0L,
      },
      0L,
    )
    is Some(rows) &&
    @canonical.nfc_lf_construction_extent(field_units) is Some(normalization) &&
    publication_inventory_add(rows, {
      record_headers: normalization.record_headers,
      reference_slots: normalization.reference_slots,
      scalar_words: normalization.scalar_words,
      owned_utf16_units: normalization.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(rows) &&
    publication_borrowed_collection_inventory(
      {
        records: 0L,
        record_references: 0L,
        record_words: 0L,
        reference_arrays: model_count + external_models + 2L,
        reference_items: 2L * (model_count + external_models),
        scalar_arrays: 4L,
        scalar_items: 2L * (model_count + external_models),
        maps: 0L,
        map_entries: 0L,
      },
      0L,
    )
    is Some(suffix) else {
    return None
  }
  // Each child is canceled/returned before its next sibling. The complete
  // inventory String remains during root matching; the unchanged writer's
  // 3B builder/output plus 2B text envelope covers that String beside the
  // next bounded artifact emitter (<=B). No parser/tree backing is removed.
  let phase = publication_inventory_max(
    publication_inventory_max(dependencies, names),
    publication_inventory_max(rows, suffix),
  )
  publication_inventory_add(common, phase)
}
