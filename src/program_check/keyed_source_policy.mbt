///|
/// Policies at the original left/read/output boundaries of one checked keyed
/// acquisition. These are policy provenance, never a request or response grant.
pub struct KeyedAcquisitionSourcePolicies {
  left : PublicationSourcePolicy?
  request : EffectivePolicy
  output : PublicationSourcePolicy?
  original : SourceExecution
}

///|
/// Reuse the SAME target provenance walk and effective-policy owner. The left
/// and joined output are genuine checked targets, not fabricated publications.
/// Static Request attestation remains separate from correlated left values.
/// The consuming compiler must fund this construction before invoking it.
pub fn prepare_keyed_acquisition_source_policies(
  program : CheckedProgram,
  execution : KeyedExecution,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> KeyedAcquisitionSourcePolicies raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget : IdentityBudget = {
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  guard program.units.get(execution.stage) is Some(unit) else {
    raise ForeignOwner
  }
  let mut original = None
  for check in unit.source_execution {
    identity_charge(budget, 1)
    if check.kind is KeyedRequest(selected) &&
      physical_equal(selected, execution) &&
      physical_equal(check.subject.owner, source_identity(program)) &&
      check.subject.stage == execution.stage {
      guard original is None else { raise ForeignOwner }
      original = Some(check)
    }
  }
  guard original is Some(original) else { raise ForeignOwner }
  let left = prepare_target_source_policy(
    unit,
    execution.stage,
    @sourceviews.keyed_join_left(execution.join),
    budget,
    producers=Some(program.units),
  )
  let output = prepare_target_source_policy(
    unit,
    execution.stage,
    @pipeline.Step(@sourceviews.keyed_join_step(execution.join)),
    budget,
    producers=Some(program.units),
  )
  let occurrences = match left {
    Some(policy) => policy.effective.occurrences.copy()
    None => []
  }
  let unknown = match left {
    Some(policy) =>
      policy.unknown_provenance ||
      (
        policy.effective.classification == @environment.Unknown &&
        occurrences.is_empty()
      )
    None => true
  }
  guard original.subject.request is @sourceviews.Keyed(_, request) else {
    raise ForeignOwner
  }
  if @sourceviews.parameterized_keyed_request_field_count(request) > 0 {
    occurrences.push(KeyedStaticRequestPolicy(original))
  }
  let request = prepare_effective_policy(occurrences, unknown, budget)
  { left, request, output, original, }
}
