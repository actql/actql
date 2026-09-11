///|
pub(all) enum ProgramReferenceIssue {
  InvalidLimits
  ForeignSource
  ForeignValues
  ForeignPipeline(Int)
  WorkLimit
} derive(Eq, Debug)

///|
struct ProgramReferences {
  stages : StageContexts
  references : @program_refs.ParameterValues
  work : Int
}

///|
/// Join complete source-role use projections to the existing stage checks.
/// Does not certify complete Input/Effect admission or executable readiness.
pub fn attach_program_references(
  stages : StageContexts,
  references : @program_refs.ParameterValues,
  max_work~ : Int,
) -> Result[ProgramReferences, ProgramReferenceIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let inventory = @program_refs.usage_inventory(
    @program_refs.parameter_usage(references),
  )
  let operations = @stages.bound_operations(stages.operations)
  let source = @stages.operations_source(operations)
  if !physical_equal(
      source,
      @request_slots.source(@program_refs.requests(inventory)),
    ) {
    return Err(ForeignSource)
  }
  if !physical_equal(
      @program_refs.parameter_values(references),
      @references.bound_values(@stages.bound_program_index(stages.operations)),
    ) {
    return Err(ForeignValues)
  }
  let reference_work = @program_refs.parameter_work(references)
  if stages.work > max_work || reference_work > max_work - stages.work {
    return Err(WorkLimit)
  }
  let mut work = stages.work + reference_work
  for i in 0..<@stages.stage_count(source) {
    if work == max_work {
      return Err(WorkLimit)
    }
    work += 1
    let source_stage = @stage_body.stage(
      @stage_body.parameter_body(
        @program_refs.stage_uses(inventory, i).unwrap(),
      ),
    )
    let checked_stage = @stages.operations_stage_at(operations, i).unwrap()
    if !physical_equal(
        @parameter_slots.pipeline(@stages.collection(source_stage)),
        @parameter_slots.pipeline(@stages.collection(checked_stage)),
      ) {
      return Err(ForeignPipeline(i))
    }
  }
  Ok({ stages, references, work, })
}

///|
pub fn program_reference_stages(value : ProgramReferences) -> StageContexts {
  value.stages
}

///|
pub fn program_reference_values(
  value : ProgramReferences,
) -> @program_refs.ParameterValues {
  value.references
}

///|
pub fn program_reference_work(value : ProgramReferences) -> Int {
  value.work
}
