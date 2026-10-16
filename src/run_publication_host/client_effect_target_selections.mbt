///|
pub(all) enum ClientEffectUpdateTargetIssue {
  Publication(@update_targets.UpdateTargetIssue)
  ForeignEnvironment
  ForeignSelection
  InvalidMaterials
  OriginalOwnerRequired
  ForeignRun
  Limit
  Encoding
}

///|
/// Concrete checked occurrence evidence. Alias names, current grants, captured
/// rows and SET values are deliberately absent from this identity projection.
priv struct ClientEffectUpdateTargetSelection {
  stage_index : Int
  effect_id : String
  target_ref : String
  mapping_ref : String
  mapping_cid : String
  check_environment_cid : String
  installation_binding_cid : String
  installation_owner_cid : String
} derive(Eq)

///|
/// Retained by the existing checked preparation, never an execution permit.
priv struct ClientEffectUpdateTargetSelections {
  wire : String
}

///|
fn client_effect_target_selection_order(
  left : ClientEffectUpdateTargetSelection,
  right : ClientEffectUpdateTargetSelection,
) -> Int {
  if left.stage_index < right.stage_index {
    -1
  } else if left.stage_index > right.stage_index {
    1
  } else {
    @canonical_value.compare_utf16(left.effect_id, right.effect_id)
  }
}

///|
fn encode_client_effect_target_selections(
  entries : Array[ClientEffectUpdateTargetSelection],
) -> Result[ClientEffectUpdateTargetSelections, ClientEffectUpdateTargetIssue] {
  if entries.is_empty() || entries.length() > 1024 {
    return Err(Limit)
  }
  let entries = entries.copy()
  entries.sort_by(client_effect_target_selection_order)
  for index in 1..<entries.length() {
    if client_effect_target_selection_order(entries[index - 1], entries[index]) ==
      0 {
      return Err(ForeignSelection)
    }
  }
  let wire = try {
    let writer = @encode.writer(65536, 8192, 4)
    @encode.begin_array(writer)
    for entry in entries {
      @encode.begin_object(writer)
      @encode.key(writer, "check_environment_cid")
      @encode.string_value(writer, entry.check_environment_cid)
      @encode.key(writer, "effect_id")
      @encode.string_value(writer, entry.effect_id)
      @encode.key(writer, "installation_binding_cid")
      @encode.string_value(writer, entry.installation_binding_cid)
      @encode.key(writer, "installation_owner_cid")
      @encode.string_value(writer, entry.installation_owner_cid)
      @encode.key(writer, "mapping_cid")
      @encode.string_value(writer, entry.mapping_cid)
      @encode.key(writer, "mapping_ref")
      @encode.string_value(writer, entry.mapping_ref)
      @encode.key(writer, "stage_index")
      @encode.number_value(writer, entry.stage_index.to_double())
      @encode.key(writer, "target_ref")
      @encode.string_value(writer, entry.target_ref)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  Ok({ wire, })
}

///|
/// Join the ordinary checker's concrete Effect inventory to the exact
/// publication already used during lowering. Full and short spelling use this
/// same join; resolving a logical alias again here would change the owner.
fn prepare_client_effect_target_selections(
  candidate : @checked.EffectProgramStaticCandidate,
  publication : @update_targets.UpdateTargetPublication?,
  max_work : Int,
) -> Result[ClientEffectUpdateTargetSelections?, ClientEffectUpdateTargetIssue] {
  guard publication is Some(publication) else { return Ok(None) }
  let environment = @checked.effect_program_static_environment(candidate)
  if !physical_equal(
      environment,
      @update_targets.update_target_publication_environment(publication),
    ) ||
    @environment.cid(environment) !=
    @environment.cid(
      @update_targets.update_target_publication_environment(publication),
    ) {
    return Err(ForeignEnvironment)
  }
  let shapes = @stage_results.effect_mapping_rules_shapes(
    @stage_results.effect_static_candidate_mapping_rules(
      @checked.effect_program_static_effects(candidate),
    ),
  )
  let count = @stage_results.effect_mapping_shape_count(shapes)
  if count > max_work {
    return Err(Limit)
  }
  // Each lookup receives a disjoint share of the declared work budget.
  let lookup_work = if count == 0 { 0 } else { (max_work - count) / count }
  let entries : Array[ClientEffectUpdateTargetSelection] = []
  for index in 0..<count {
    let shape = @stage_results.effect_mapping_shape_at(shapes, index).unwrap()
    let header = @stage_results.effect_result_binding_header(
      @stage_results.effect_mapping_shape_effect(shape),
    )
    if @syntax.effect_header_kind(header) != "update" {
      continue
    }
    let mapping = @stage_results.effect_mapping_shape_contract(shape)
    let target_ref = @environment.mapping_shape_target(mapping)
    let mapping_ref = @environment.mapping_shape_reference(mapping)
    let resolved = match
      @update_targets.resolve_concrete_update_target_binding(
        publication, target_ref, mapping_ref, lookup_work,
      ) {
      Ok(value) => value
      // Existing explicit targets outside this positive publication retain
      // their prior path. Logical lowering cannot produce that exception.
      Err(@update_targets.UpdateTargetIssue::UnresolvedTarget) => continue
      Err(issue) => return Err(Publication(issue))
    }
    let (environment_cid, mapping_cid, installation_binding_cid) = @update_targets.resolved_update_target_identity(
      resolved,
    )
    let installation_owner_cid = @update_targets.resolved_update_target_owner_cid(
      resolved,
    )
    if @update_targets.resolved_update_target(resolved) !=
      (target_ref, mapping_ref) ||
      environment_cid != @environment.cid(environment) ||
      mapping_cid != @environment.mapping_shape_cid(mapping) ||
      !valid_client_request_cid(installation_binding_cid) ||
      !valid_client_request_cid(installation_owner_cid) {
      return Err(ForeignSelection)
    }
    entries.push({
      stage_index: @syntax.effect_header_stage(header),
      effect_id: @syntax.effect_header_id(header),
      target_ref,
      mapping_ref,
      mapping_cid,
      check_environment_cid: environment_cid,
      installation_binding_cid,
      installation_owner_cid,
    })
  }
  if entries.is_empty() {
    Ok(None)
  } else {
    encode_client_effect_target_selections(entries).map(Some)
  }
}

///|
/// Inspect only the original checked static selection. This grants no Run,
/// request, installation lifetime, Preview or write authority.
pub fn prepared_client_effect_target_selections(
  prepared : PreparedClientEffectComputation,
) -> String? {
  prepared.target_selections.map(value => value.wire)
}

///|
fn client_effect_target_selections_cid(
  prepared : PreparedClientEffectComputation,
) -> String? {
  prepared.target_selections.map(value => {
    "sha256:" + @sha.hex(@utf8.encode(value.wire))
  })
}

///|
/// Restoration reads concrete evidence against the SAVED checked Program and
/// environment. It never takes a fresh publication or resolves an alias. The
/// caller must still reproduce compilation, admit saved invocation/authority,
/// and match an independently selected original Run CID before returning it.
fn admit_client_effect_target_selections(
  candidate : @checked.EffectProgramStaticCandidate,
  wire : String,
) -> Result[ClientEffectUpdateTargetSelections, ClientEffectUpdateTargetIssue] {
  let source = match
    @source.parse_json_bytes(
      @utf8.encode(wire),
      { max_input_bytes: 65536, max_nodes: 8192, max_depth: 4, },
      source_path="Original Effect Target Selections",
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterials)
  }
  let root = match
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 4,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterials)
  }
  let values = match @decode.elements(root) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterials)
  }
  if values.is_empty() || values.length() > 1024 {
    return Err(InvalidMaterials)
  }
  let shapes = @stage_results.effect_mapping_rules_shapes(
    @stage_results.effect_static_candidate_mapping_rules(
      @checked.effect_program_static_effects(candidate),
    ),
  )
  let count = @stage_results.effect_mapping_shape_count(shapes)
  let environment_cid = @environment.cid(
    @checked.effect_program_static_environment(candidate),
  )
  if count > 1024 {
    return Err(Limit)
  }
  let entries : Array[ClientEffectUpdateTargetSelection] = []
  for value in values {
    let object = match
      @decode.closed_object(value, [
        "check_environment_cid", "effect_id", "installation_binding_cid", "installation_owner_cid",
        "mapping_cid", "mapping_ref", "stage_index", "target_ref",
      ]) {
      Ok(value) => value
      Err(_) => return Err(InvalidMaterials)
    }
    let text = fn(name : String) -> String? {
      match @decode.lookup(object, name) {
        None => None
        Some(value) => @decode.text(value).to_option()
      }
    }
    guard @decode.lookup(object, "stage_index") is Some(stage) &&
      @decode.int32(stage) is Ok(stage_index) &&
      stage_index >= 0 &&
      text("effect_id") is Some(effect_id) &&
      text("target_ref") is Some(target_ref) &&
      text("mapping_ref") is Some(mapping_ref) &&
      text("mapping_cid") is Some(mapping_cid) &&
      text("check_environment_cid") == Some(environment_cid) &&
      text("installation_binding_cid") is Some(installation_binding_cid) &&
      valid_client_request_cid(installation_binding_cid) &&
      text("installation_owner_cid") is Some(installation_owner_cid) &&
      valid_client_request_cid(installation_owner_cid) else {
      return Err(InvalidMaterials)
    }
    let mut matched = false
    for index in 0..<count {
      let shape = @stage_results.effect_mapping_shape_at(shapes, index).unwrap()
      let header = @stage_results.effect_result_binding_header(
        @stage_results.effect_mapping_shape_effect(shape),
      )
      let mapping = @stage_results.effect_mapping_shape_contract(shape)
      if @syntax.effect_header_kind(header) == "update" &&
        @syntax.effect_header_stage(header) == stage_index &&
        @syntax.effect_header_id(header) == effect_id &&
        @environment.mapping_shape_target(mapping) == target_ref &&
        @environment.mapping_shape_reference(mapping) == mapping_ref &&
        @environment.mapping_shape_cid(mapping) == mapping_cid {
        if matched {
          return Err(ForeignSelection)
        }
        matched = true
      }
    }
    if !matched {
      return Err(ForeignSelection)
    }
    entries.push({
      stage_index,
      effect_id,
      target_ref,
      mapping_ref,
      mapping_cid,
      check_environment_cid: environment_cid,
      installation_binding_cid,
      installation_owner_cid,
    })
  }
  let restored = match encode_client_effect_target_selections(entries) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if restored.wire != wire {
    return Err(InvalidMaterials)
  }
  Ok(restored)
}

///|
/// Release only selection evidence held by the exact admitted original Run.
/// The existing Run/compilation/preparation chain is the custody owner; an
/// empty normalization journal cannot substitute for these selected tuples.
pub fn restore_client_effect_run_target_selections(
  materials : ClientEffectRunMaterials,
) -> Result[String?, ClientEffectUpdateTargetIssue] {
  if !physical_equal(materials.prepared, materials.compilation.owner) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) {
    return Err(ForeignRun)
  }
  Ok(prepared_client_effect_target_selections(materials.prepared))
}
