///|
/// Preserve the checker's original nominal outcome constructor across the
/// policy-only continuation; no external caller manufactures Checked values.
pub fn observe_supplement_checked_request_value_policies(
  original : CheckedProgram,
  evidence : Array[HostRequestValuePolicyEvidence],
  limits : CompileLimits,
) -> (Result[CheckOutcome, LocalConstructionFailure], Int, Bool) {
  let (result, spent, complete) = observe_supplement_checked_request_value_policies_owned(
    original, evidence, limits,
  )
  (result.map(value => Checked(value)), spent, complete)
}

///|
/// Rebind only policy-sensitive execution/publication DATA on the exact
/// checked Program. Identity, Parameters, Catalog, typed pipelines, contracts,
/// capacity proofs and all other completed semantic facts remain original.
/// Nominal Host evidence still passes the existing full provenance matcher.
/// This neither checks a new Program nor grants Source/Effect permission.
fn observe_supplement_checked_request_value_policies_owned(
  original : CheckedProgram,
  evidence : Array[HostRequestValuePolicyEvidence],
  limits : CompileLimits,
) -> (Result[CheckedProgram, LocalConstructionFailure], Int, Bool) {
  if !compile_limits_valid(limits) {
    return (Err(InvalidLimits), 0, false)
  }
  let budget = IdentityBudget::{
    work: limits.work,
    bytes: limits.artifacts.bytes,
    nodes: limits.artifacts.nodes,
    depth: limits.artifacts.depth,
  }
  let result = Ok(
    supplement_checked_request_value_policies(original, evidence, budget),
  ) catch {
    issue => Err(Units(issue))
  }
  // Existing transactional subconstructors commit their meter on success.
  // Failure therefore charges the full selected envelope conservatively,
  // rather than reporting an invented complete/zero-work failed traversal.
  let complete = result is Ok(_)
  (
    result,
    if complete {
      limits.work - budget.work
    } else {
      limits.work
    },
    complete,
  )
}

///|
fn supplement_checked_request_value_policies(
  original : CheckedProgram,
  evidence : Array[HostRequestValuePolicyEvidence],
  budget : IdentityBudget,
) -> CheckedProgram raise UnitBuildFailure {
  let checks = prepare_source_execution(
    original.identity,
    budget,
    request_value_policies=evidence,
    original=Some(original.units[0].source_execution),
  )
  identity_charge(budget, original.units.length())
  let completed : Array[BuiltUnit] = []
  for original_unit in original.units {
    let unit = { ..original_unit, source_execution: checks, }
    identity_charge(budget, unit.publications.length())
    let publications : Array[PublicationExecution] = []
    for publication in unit.publications {
      let source_policy = prepare_publication_source_policy(
        unit,
        @context.publication_row_limit_result(publication.selection),
        budget,
        producers=Some(completed),
      )
      publications.push({ ..publication, source_policy, })
    }
    completed.push({ ..unit, publications, })
  }
  // Keyed input proofs keep the original converted proof and producer. Only
  // their policy-bearing execution edge changes; no bound is re-derived.
  let keyed : Map[(Int, Int), SourceExecution] = Map([])
  for check in checks {
    identity_charge(budget, 1)
    if check.kind is KeyedRequest(binding) {
      keyed[(binding.stage, binding.index)] = check
    }
  }
  identity_charge(budget, original.keyed_input_proofs.length())
  let keyed_input_proofs = original.keyed_input_proofs.map(proof => {
    guard proof.execution.kind is KeyedRequest(binding) &&
      keyed.get((binding.stage, binding.index)) is Some(execution) &&
      execution.kind is KeyedRequest(selected) &&
      physical_equal(selected, binding) else {
      raise ForeignOwner
    }
    { ..proof, execution, }
  })
  { ..original, units: completed, keyed_input_proofs, }
}

///|
/// Preserve the original Effect headers and supplied input with the SAME
/// policy-only computation continuation. No CheckedProgram is upgraded into
/// a new Effect inventory or an apply/admission witness.
pub fn observe_supplement_effect_request_value_policies(
  original : EffectComputationCandidate,
  evidence : Array[HostRequestValuePolicyEvidence],
  limits : CompileLimits,
) -> (Result[EffectComputationCandidate, EffectComputationIssue], Int, Bool) {
  let (result, spent, complete) = observe_supplement_checked_request_value_policies_owned(
    original.checked,
    evidence,
    limits,
  )
  let selected = match result {
    Err(issue) => Err(Computation(issue))
    Ok(checked) => Ok({ ..original, checked, })
  }
  (selected, spent, complete)
}
