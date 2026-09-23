///|
pub(all) struct EffectStaticCandidateLimits {
  max_members : Int
  max_work : Int
  max_value_nodes : Int
  max_value_depth : Int
  max_value_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum EffectStaticCandidateIssue {
  InvalidLimits
  MemberLimit
  ForeignEnvironment
  WorkLimit
  Results(EffectResultBindingIssue)
  MappingShapes(EffectMappingShapeIssue)
  MappingRules(EffectMappingRuleIssue)
  MappingLiterals(EffectMappingLiteralIssue)
  CommandTargets(EffectCommandTargetIssue)
  IncompleteInventory
}

///|
/// Static Effect closure over one checked Stage Result owner and one admitted
/// Environment. This is deliberately not a CheckedEffectSet or execution
/// permit: the enclosing checked Program must still bind that Environment,
/// registered conversions and Command inputs must be proved, and captured
/// values, current authority, Preview, and apply preflight remain separate.
pub struct EffectStaticCandidate {
  results : EffectResultBindings
  mapping_shapes : EffectMappingShapes
  mapping_rules : EffectMappingRules
  mapping_literals : EffectMappingLiterals
  command_targets : EffectCommandTargets
  work : Int
}

///|
pub fn effect_static_candidate_results(
  candidate : EffectStaticCandidate,
) -> EffectResultBindings {
  candidate.results
}

///|
pub fn effect_static_candidate_mapping_rules(
  candidate : EffectStaticCandidate,
) -> EffectMappingRules {
  candidate.mapping_rules
}

///|
pub fn effect_static_candidate_mapping_literals(
  candidate : EffectStaticCandidate,
) -> EffectMappingLiterals {
  candidate.mapping_literals
}

///|
pub fn effect_static_candidate_command_targets(
  candidate : EffectStaticCandidate,
) -> EffectCommandTargets {
  candidate.command_targets
}

///|
pub fn effect_static_candidate_work(candidate : EffectStaticCandidate) -> Int {
  candidate.work
}

///|
/// Combine the existing bounded static passes without admitting a second
/// Environment or silently dropping Command or Mapping members. The limits
/// cover these passes and retained literal values; Environment admission is
/// an earlier, separately metered obligation of the enclosing Program check.
pub fn prepare_effect_static_candidate(
  headers : @syntax.EffectHeaders,
  checked : Checked,
  expected_environment : @environment.WireEnvironment,
  mappings : @environment.MappingContractShapes,
  catalogs : @environment.CatalogContents,
  limits : EffectStaticCandidateLimits,
) -> Result[EffectStaticCandidate, EffectStaticCandidateIssue] {
  if limits.max_members < 0 ||
    limits.max_work < 0 ||
    limits.max_value_nodes < 0 ||
    limits.max_value_depth < 0 ||
    limits.max_value_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if @syntax.effect_header_count(headers) > limits.max_members {
    return Err(MemberLimit)
  }
  if !physical_equal(
      expected_environment,
      @environment.mapping_shape_environment(mappings),
    ) ||
    !physical_equal(
      @environment.mapping_shape_environment(mappings),
      @environment.contract_registry_environment(
        @environment.catalog_registry(catalogs),
      ),
    ) {
    return Err(ForeignEnvironment)
  }
  let mut remaining = limits.max_work
  let header_work = @syntax.effect_headers_work(headers)
  if header_work > remaining {
    return Err(WorkLimit)
  }
  remaining -= header_work
  let results = match bind_effect_results(headers, checked, remaining) {
    Ok(value) => value
    Err(issue) => return Err(Results(issue))
  }
  remaining -= effect_result_bindings_work(results)
  let mapping_shapes = match
    bind_effect_mapping_shapes(results, mappings, remaining) {
    Ok(value) => value
    Err(issue) => return Err(MappingShapes(issue))
  }
  remaining -= effect_mapping_shapes_work(mapping_shapes)
  let mapping_rules = match
    bind_effect_mapping_rules(mapping_shapes, remaining) {
    Ok(value) => value
    Err(issue) => return Err(MappingRules(issue))
  }
  remaining -= effect_mapping_rules_work(mapping_rules)
  let mapping_literals = match
    admit_effect_mapping_literals(mapping_rules, {
      max_work: remaining,
      max_value_nodes: limits.max_value_nodes,
      max_value_depth: limits.max_value_depth,
      max_value_text_bytes: limits.max_value_text_bytes,
    }) {
    Ok(value) => value
    Err(issue) => return Err(MappingLiterals(issue))
  }
  remaining -= effect_mapping_literals_usage(mapping_literals).0
  let command_targets = match
    bind_effect_command_targets(results, catalogs, remaining) {
    Ok(value) => value
    Err(issue) => return Err(CommandTargets(issue))
  }
  remaining -= effect_command_targets_work(command_targets)
  if effect_mapping_rule_count(mapping_rules) +
    effect_command_target_count(command_targets) !=
    effect_result_binding_count(results) {
    return Err(IncompleteInventory)
  }
  Ok({
    results,
    mapping_shapes,
    mapping_rules,
    mapping_literals,
    command_targets,
    work: limits.max_work - remaining,
  })
}
