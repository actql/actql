///|
pub(all) struct SourcePreparationLimits {
  body : @stage_body.Limits
  uses : @parameter_slots.Limits
  references : @program_refs.Limits
  identity : ProgramIdentityLimits
  max_bindings : Int
}

///|
pub enum SourcePreparationIssue {
  InvalidLimits
  BudgetExceeded
  Bindings(SourceBindingsIssue)
  References(PreparedReferencesIssue)
  Sources(ProgramSourcesIssue)
  Identity(ProgramIdentityIssue)
}

///|
/// Prepare source identities without separately supplied reference or Binding
/// inventories. Effective values and request slots come from the retained owner.
/// Host Binding requirements remain requirements; no invocation or successful
/// CheckedProgram is manufactured by source identity preparation.
pub fn prepare_program_source_identity(
  operations : OperationProfileChecks,
  limits : SourcePreparationLimits,
) -> Result[ProgramSourceIdentity, SourcePreparationIssue] {
  let cap = limits.identity.max_work
  if cap < 0 ||
    limits.identity.max_stages < 0 ||
    limits.identity.max_hash_bytes < 0 ||
    limits.identity.max_hash_nodes < 0 ||
    limits.identity.max_depth < 0 ||
    limits.max_bindings < 0 {
    return Err(InvalidLimits)
  }
  if operations.work >= cap {
    return Err(BudgetExceeded)
  }
  let preparation = operations.preparation
  // Reserve the source-owner join before either branch can retain its results.
  let bindings = match
    collect_source_bindings(
      preparation,
      preparation.usage.work + (cap - operations.work - 1),
      limits.max_bindings,
    ) {
    Ok(v) => v
    Err(e) => return Err(Bindings(e))
  }
  let extra = bindings.work - preparation.usage.work
  let stages = preparation.sources.capacity.context.rows.requests.contexts
  let references = match
    prepare_program_references(
      operations,
      limits.body,
      limits.uses,
      limits.references,
      max_work=stages.work + (cap - operations.work - extra - 1),
    ) {
    Ok(v) => v
    Err(e) => return Err(References(e))
  }
  let sources = match
    bind_program_sources(operations, references, bindings, cap) {
    Ok(v) => v
    Err(e) => return Err(Sources(e))
  }
  match identify_program_sources(sources, limits.identity) {
    Ok(v) => Ok(v)
    Err(e) => Err(Identity(e))
  }
}
