///|
pub(all) enum ProgramSourcesIssue {
  InvalidLimits
  ForeignStages
  ForeignRequestSlots
  ForeignPreparation
  BudgetExceeded
} derive(Eq, Debug)

///|
struct ProgramSourceChecks {
  operations : OperationProfileChecks
  references : ProgramReferences
  bindings : SourceBindingRequirements
  work : Int
}

///|
/// Bind whole-Program declaration use and selected Parameter values to the
/// source requests and checked operations that consume them. Remaining Host
/// Bindings are retained, not interpreted as admitted opaque references.
pub fn bind_program_sources(
  operations : OperationProfileChecks,
  references : ProgramReferences,
  bindings : SourceBindingRequirements,
  max_work : Int,
) -> Result[ProgramSourceChecks, ProgramSourcesIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let preparation = operations.preparation
  if !physical_equal(preparation, bindings.preparation) {
    return Err(ForeignPreparation)
  }
  let requests = preparation.sources.capacity.context.rows.requests
  let stages = requests.contexts
  if !physical_equal(stages, references.stages) {
    return Err(ForeignStages)
  }
  let inventory = @program_refs.usage_inventory(
    @program_refs.parameter_usage(references.references),
  )
  // The same Program bytes do not substitute for the admitted declarations
  // and source-role slots used by the concrete request checks.
  if !physical_equal(requests.slots, @program_refs.requests(inventory)) {
    return Err(ForeignRequestSlots)
  }
  let reference_work = references.work - stages.work
  let binding_work = bindings.work - preparation.usage.work
  if operations.work >= max_work ||
    reference_work > max_work - operations.work - 1 ||
    binding_work > max_work - operations.work - 1 - reference_work {
    return Err(BudgetExceeded)
  }
  Ok({
    operations,
    references,
    bindings,
    work: operations.work + reference_work + binding_work + 1,
  })
}

///|
pub fn program_sources_operations(
  v : ProgramSourceChecks,
) -> OperationProfileChecks {
  v.operations
}

///|
pub fn program_sources_references(v : ProgramSourceChecks) -> ProgramReferences {
  v.references
}

///|
pub fn program_sources_bindings(
  v : ProgramSourceChecks,
) -> SourceBindingRequirements {
  v.bindings
}

///|
pub fn program_sources_work(v : ProgramSourceChecks) -> Int {
  v.work
}

///|
/// Unbound semantics from this assembly's exact source inventory. Stage/Unit
/// definition envelopes, execution readiness and issuer admission remain separate.
pub fn program_sources_stage_semantics(
  v : ProgramSourceChecks,
  index : Int,
) -> @program_refs.StageSemantics? {
  @program_refs.stage_semantics_at(
    @program_refs.parameter_usage(v.references.references),
    index,
  )
}

///|
/// Prepare source semantics using the exact inventory bound to this assembly.
/// This does not discharge remaining static or runtime admission obligations.
pub fn program_sources_semantics(
  v : ProgramSourceChecks,
  limits : @program_refs.ProgramSemanticsLimits,
) -> Result[@program_refs.ProgramSemantics, @program_refs.ProgramSemanticsIssue] {
  @program_refs.prepare_program_semantics(
    @program_refs.parameter_usage(v.references.references),
    limits,
  )
}
