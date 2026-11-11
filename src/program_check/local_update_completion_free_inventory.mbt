///|
/// A distinct applicability projection over the original computation and its
/// closed update owners. It cannot be used as a mapped-create inventory.
struct LocalUpdateCompletionFreeInventory {
  owner : EffectProgramStaticCandidate
  audited_work : Int
}

///|
/// Retain this audit when the existing checker closes the static Effect. The
/// computation audit, header, selector, changes and Mapping owners all share
/// the same finite work ceiling. No current JSON or check-success flag can
/// substitute for those original owners.
fn audit_local_update_completion_free(
  computation : EffectComputationCandidate,
  effects : @results.EffectStaticCandidate,
) -> CompletionFreeAudit {
  let checked = computation.checked
  let work = match checked.completion_free_audit {
    Complete(work) => work
    ProfileNotInstalled => return ProfileNotInstalled
    CompletionObserved => return CompletionObserved
  }
  audit_local_update_mapping(computation, effects, work)
}

///|
fn audit_local_update_mapping(
  computation : EffectComputationCandidate,
  effects : @results.EffectStaticCandidate,
  work : Int,
) -> CompletionFreeAudit {
  let checked = computation.checked
  let headers = computation.headers
  if @syntax.effect_header_count(headers) != 1 {
    return ProfileNotInstalled
  }
  let header = @syntax.effect_header_at(headers, 0).unwrap()
  if @syntax.effect_header_kind(header) != "update" ||
    !@syntax.effect_header_contract_ref(header).has_prefix("mapping:") {
    return ProfileNotInstalled
  }
  let results = @results.effect_static_candidate_results(effects)
  let rules = @results.effect_static_candidate_mapping_rules(effects)
  let literals = @results.effect_static_candidate_mapping_literals(effects)
  if !physical_equal(
      @results.effect_result_bindings_owner(results),
      checked_stage_results(checked),
    ) ||
    !physical_equal(@results.effect_result_bindings_headers(results), headers) ||
    !physical_equal(@results.effect_mapping_literals_rules(literals), rules) ||
    @results.effect_result_binding_count(results) != 1 ||
    @results.effect_mapping_rule_count(rules) != 1 {
    return ProfileNotInstalled
  }
  let rule = @results.effect_mapping_rule_at(rules, 0).unwrap()
  let binding = @results.effect_mapping_shape_effect(
    @results.effect_mapping_rule_effect(rule),
  )
  if !physical_equal(
      binding,
      @results.effect_result_binding_at(results, 0).unwrap(),
    ) ||
    !physical_equal(@results.effect_result_binding_header(binding), header) ||
    @results.effect_result_binding_result(binding) is None ||
    @environment.mapping_conversion_count(
      @results.effect_mapping_rule_conversions(rule),
    ) !=
    0 {
    return ProfileNotInstalled
  }
  let static_work = @results.effect_static_candidate_work(effects)
  if work < 0 || static_work < 0 || static_work > 10000 - work {
    return ProfileNotInstalled
  }
  let mut remaining = 10000 - work - static_work
  let (kind, selector, fields) = @environment.mapping_permission_rule(
    @results.effect_mapping_rule_selection(rule),
  )
  if kind != "update" || selector != "id" {
    return ProfileNotInstalled
  }
  // These cursors belong to the retained, checked header; they are not an
  // independently supplied selector or change document.
  let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
  guard @decode.lookup(body, "id") is Some(_) &&
    @decode.lookup(body, "set") is Some(changes) else {
    return ProfileNotInstalled
  }
  let count = @decode.object_length(changes).unwrap()
  if count == 0 || count != fields.length() || count > remaining {
    return ProfileNotInstalled
  }
  remaining -= count
  let mut selector_count = 0
  let mut field_changes = 0
  for index in 0..<@results.effect_result_field_binding_count(binding) {
    if remaining <= 0 {
      return ProfileNotInstalled
    }
    remaining -= 1
    match
      @results.effect_result_field_binding_role(
        @results.effect_result_field_binding_at(binding, index).unwrap(),
      ) {
      EffectSelector => selector_count += 1
      EffectValue(_) => field_changes += 1
      _ => return ProfileNotInstalled
    }
  }
  if selector_count != 1 {
    return ProfileNotInstalled
  }
  let mut literal_changes = 0
  for index in 0..<@results.effect_mapping_literal_count(literals) {
    if remaining <= 0 {
      return ProfileNotInstalled
    }
    remaining -= 1
    let literal = @results.effect_mapping_literal_at(literals, index).unwrap()
    if !physical_equal(@results.effect_mapping_literal_rule(literal), rule) ||
      @results.effect_mapping_literal_origin(literal) != @results.InlineSet {
      return ProfileNotInstalled
    }
    // Authored update literals are admitted with authored_fields=true. This
    // slice accepts scalar leaves only; it cannot certify nested omissions or
    // an omitted write produced by a Mapping null policy.
    match @results.effect_mapping_literal_value(literal) {
      Written(_) => ()
      Omitted => return CompletionObserved
    }
    let target = @results.effect_mapping_literal_target(literal)
    let entry = @decode.lookup(@decode.open_object(changes).unwrap(), target).unwrap()
    let value = @decode.lookup(@decode.open_object(entry).unwrap(), "literal").unwrap()
    if @decode.object_length(value) is Some(_) ||
      @decode.array_length(value) is Some(_) {
      return ProfileNotInstalled
    }
    literal_changes += 1
  }
  if field_changes + literal_changes != count {
    return ProfileNotInstalled
  }
  Complete(10000 - remaining)
}

///|
pub fn effect_program_local_update_completion_free_inventory(
  candidate : EffectProgramStaticCandidate,
) -> Result[LocalUpdateCompletionFreeInventory, CompletionFreeInventoryIssue] {
  match candidate.local_update_completion_free_audit {
    Complete(work) => Ok({ owner: candidate, audited_work: work, })
    ProfileNotInstalled => Err(ProfileNotInstalled)
    CompletionObserved => Err(CompletionObserved)
  }
}

///|
pub fn local_update_completion_free_inventory_matches(
  inventory : LocalUpdateCompletionFreeInventory,
  candidate : EffectProgramStaticCandidate,
) -> Bool {
  physical_equal(inventory.owner, candidate)
}

///|
pub fn local_update_completion_free_inventory_work(
  inventory : LocalUpdateCompletionFreeInventory,
) -> Int {
  inventory.audited_work
}

///|
/// Same original computation requirement closure plus the original static
/// update/selector/Mapping audit. This is normalization custody, not support,
/// Source, Model, Preview, apply or physical resource authority.
struct LocalCommonUpdateCompletionFreeInventory {
  owner : EffectProgramStaticCandidate
  computation : LocalCommonNormalizationInventory
  audited_work : Int
}

///|
pub fn effect_program_common_update_completion_free_inventory(
  candidate : EffectProgramStaticCandidate,
) -> Result[
  LocalCommonUpdateCompletionFreeInventory,
  CompletionFreeInventoryIssue,
] {
  let computation = match
    audit_local_common_normalization_inventory(
      candidate.computation.checked,
      10000,
    ) {
    Ok(value) => value
    Err(CompletionObserved) => return Err(CompletionObserved)
    Err(_) => return Err(ProfileNotInstalled)
  }
  // This new immutable profile certifies only actual zero-entry inventories.
  // A sort/projection/default/Source completion is never discarded.
  if local_common_normalization_entry_count(computation) != 0 {
    return Err(CompletionObserved)
  }
  let work = local_common_normalization_inventory_work(computation)
  match
    audit_local_update_mapping(candidate.computation, candidate.effects, work) {
    Complete(audited_work) =>
      Ok({ owner: candidate, computation, audited_work, })
    CompletionObserved => Err(CompletionObserved)
    ProfileNotInstalled => Err(ProfileNotInstalled)
  }
}

///|
pub fn local_common_update_completion_free_inventory_matches(
  inventory : LocalCommonUpdateCompletionFreeInventory,
  candidate : EffectProgramStaticCandidate,
) -> Bool {
  physical_equal(inventory.owner, candidate) &&
  inventory.audited_work >= 0 &&
  local_common_normalization_inventory_matches(
    inventory.computation,
    candidate.computation.checked,
  )
}
