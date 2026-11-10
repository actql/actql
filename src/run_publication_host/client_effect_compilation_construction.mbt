///|
/// The existing cold material reader retains these SAME checked originals.
/// This fixed view is sizing input, not a compiler, Run, grant or reservation.
pub struct ClientEffectCompilationConstructionInput {
  priv owner : PreparedClientEffectComputation
  priv components : Array[ClientInferPlanGraph]
  priv normalization : ClientEffectNormalizationInventory?
}

///|
/// The geometry belongs to the original Effect input, not to a second pure
/// compiler. Its arrays describe actual wire/container roles for a Native ABI
/// projection; logical bytes are never a physical raw-allocation measurement.
pub struct ClientEffectCompilationConstruction {
  priv input : ClientEffectCompilationConstructionInput
  priv geometry : ClientPureCompilationConstruction
}

///|
pub fn client_effect_compilation_construction_geometry(
  value : ClientEffectCompilationConstruction,
) -> ClientPureCompilationConstruction {
  value.geometry
}

///|
pub fn client_effect_compilation_construction_matches(
  value : ClientEffectCompilationConstruction,
  owner : PreparedClientEffectComputation,
) -> Bool {
  physical_equal(value.input.owner, owner)
}

///|
// The model component wrappers are original checker/graph outputs. This finite
// entrance deliberately leaves unmeasured serialization-only families to the
// existing conservative caller recipe; it never changes their admission.
fn client_effect_construction_view(
  input : ClientEffectCompilationConstructionInput,
) -> Result[PreparedClientProgram, ClientValuesExecutablePlanIssue] {
  if input.components.is_empty() {
    return Err(TaskGraph(UnsupportedGraph))
  }
  let result = if input.components.length() == 1 {
    client_effect_compilation_original_view(
      input.owner,
      Some(input.components[0]),
      [],
    )
  } else {
    client_effect_compilation_original_view(input.owner, None, input.components)
  }
  result.map_err(_ => TaskGraph(UnsupportedGraph))
}

///|
/// Fund this returned collection envelope before measurement. The SAME graph,
/// fragments and component trees stay borrowed and funded by the caller.
/// As with the existing Model measurement, nested lowering/emitter scratch
/// and work retain their separate existing owner; this is not full capacity.
pub fn prepared_client_effect_measurement_storage(
  input : ClientEffectCompilationConstructionInput,
  limits : ClientPureCompilationLimits,
) -> Result[
  @execution.PreparationRepresentationUnits,
  ClientValuesExecutablePlanIssue,
] {
  if !client_pure_compilation_limits_valid(
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    return Err(InvalidLimits)
  }
  let value = match client_effect_construction_view(input) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_pure_measurement_storage_owned(
      value,
      input.components,
      allow_empty_results=true,
    )
    is Some(base) else {
    return Err(Encoding)
  }
  let count = @syntax.effect_header_count(
    @checked.effect_program_static_headers(input.owner.candidate),
  ).to_int64()
  let selections = input.owner.target_selections
    .map(value => value.entries.length().to_int64())
    .unwrap_or(0L)
  let headers = @checked.effect_program_static_headers(input.owner.candidate)
  let mut changes = 0L
  for index in 0..<@syntax.effect_header_count(headers) {
    guard @syntax.effect_header_at(headers, index) is Some(header) else {
      return Err(Encoding)
    }
    let body = @syntax.effect_header_body(header)
    if @decode.open_object(body) is Ok(object) &&
      @decode.lookup(object, "set") is Some(fields) {
      guard @decode.object_length(fields) is Some(count) &&
        @execution.checked_preparation_add_product(
          changes,
          count.to_int64(),
          1L,
        )
        is Some(next) else {
        return Err(Encoding)
      }
      changes = next
    }
  }
  // Per Effect: original root 1H/1R/1W; terminal pair 1H/2R;
  // terminal plus Some 2H/8R/1W; Plan-name/CID pair 1H/2R;
  // two measured geometries, each the existing 4H/4R/12W report+usage.
  // Total 13H/21R/26W. Each SET field can add a borrowed 1H/2R pair,
  // and each terminal owns its own Array. The fixed report/return frames
  // and target-selection report remain covered alongside these collections.
  guard @shape.collection_construction_extent({
      records: 13L * count + changes + 12L,
      record_references: 21L * count + 2L * changes + 24L,
      record_words: 26L * count + 32L,
      reference_arrays: 5L + count,
      reference_items: 8L * count + selections + changes + 4L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(extra) &&
    @execution.compose_preparation_representation([
      base,
      {
        record_headers: extra.record_headers,
        reference_slots: extra.reference_slots,
        scalar_words: extra.scalar_words,
        owned_utf16_units: 71L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) else {
    return Err(Encoding)
  }
  Ok(units)
}

///|
/// Measure before the actual Effect compiler emits any artifact. Existing
/// fragment/final writers share their exact schema/order/escaping rules. No
/// parser, semantic check, CID hash, compilation or physical I/O is repeated.
pub fn measure_prepared_client_effect_compilation_construction(
  input : ClientEffectCompilationConstructionInput,
  manifests : ClientCompilationManifests,
  sequence : @lower.SequenceLimits,
  limits : ClientPureCompilationLimits,
) -> Result[
  ClientEffectCompilationConstruction,
  ClientValuesExecutablePlanIssue,
] {
  let value = match client_effect_construction_view(input) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if input.normalization is Some(original) &&
    !client_effect_normalization_inventory_matches(original, input.owner) {
    return Err(TaskGraph(UnsupportedGraph))
  }
  let profiles = match input.normalization {
    None => []
    Some(original) =>
      [(client_effect_normalization_inventory_profile(original).0, ())]
  }
  measure_prepared_client_compilation_construction_owned(
    value,
    manifests,
    sequence,
    limits.max_facts,
    limits.max_witnesses,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
    input.components,
    effect=Some(input.owner),
    extra_profiles=profiles,
  ).map(geometry => { input, geometry, })
}
