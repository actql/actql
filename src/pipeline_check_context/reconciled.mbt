///|
pub(all) enum ReconciledIssue {
  InvalidLimits
  ForeignProgram
  StageCount
  ForeignStage(Int)
  ForeignEvidence(Int)
  InconsistentUsage
  BudgetExceeded
} derive(Eq, Debug)

///|
struct ReconciledContexts {
  wired : WiredStages
  snapshots : @local_inputs.ProgramEnvironmentInputs
  locals : Array[@local_inputs.ReconciledAttachment]
  usage : InputUsage
}

///|
pub fn attach_reconciled_inputs(
  wired : WiredStages,
  snapshots : @local_inputs.ProgramEnvironmentInputs,
  locals : Array[@local_inputs.ReconciledAttachment],
  max_work~ : Int,
  max_text_bytes~ : Int,
  max_local_input_nodes~ : Int,
) -> Result[ReconciledContexts, ReconciledIssue] {
  if max_work < 0 || max_text_bytes < 0 || max_local_input_nodes < 0 {
    return Err(InvalidLimits)
  }
  let operations = @stages.bound_operations(wired.stages.operations)
  if !physical_equal(
      @local_inputs.environment_program(snapshots),
      @stages.operations_source(operations),
    ) {
    return Err(ForeignProgram)
  }
  let count = wired.stages.contexts.length()
  if locals.length() != count {
    return Err(StageCount)
  }
  let cost = @local_inputs.program_environment_usage(snapshots)
  if wired.work > max_work ||
    cost.work > max_work - wired.work ||
    wired.text > max_text_bytes ||
    cost.text_bytes > max_text_bytes - wired.text ||
    cost.nodes > max_local_input_nodes {
    return Err(BudgetExceeded)
  }
  let mut work = wired.work + cost.work
  for i in 0..<count {
    let expected = @stages.operations_stage_at(operations, i).unwrap()
    if !physical_equal(@local_inputs.reconciled_stage(locals[i]), expected) {
      return Err(ForeignStage(i))
    }
    let evidence = @local_inputs.program_environment_stage(snapshots, i).unwrap()
    if !physical_equal(@local_inputs.reconciled_inputs(locals[i]), evidence) {
      return Err(ForeignEvidence(i))
    }
    let mut added = @local_inputs.reconciled_work(locals[i])
    // Both immutable owners are already charged by the retained branches.
    for
      shared in [
        @stages.collection_work(expected),
        @local_inputs.environment_usage(evidence).work,
      ] {
      if shared > added {
        return Err(InconsistentUsage)
      }
      added -= shared
    }
    if work == max_work || added > max_work - work - 1 {
      return Err(BudgetExceeded)
    }
    work += 1 + added
  }
  Ok({
    wired,
    snapshots,
    locals: locals.copy(),
    usage: {
      work,
      text_bytes: wired.text + cost.text_bytes,
      local_input_nodes: cost.nodes,
    },
  })
}

///|
pub fn reconciled_wiring(v : ReconciledContexts) -> WiredStages {
  v.wired
}

///|
pub fn reconciled_snapshots(
  v : ReconciledContexts,
) -> @local_inputs.ProgramEnvironmentInputs {
  v.snapshots
}

///|
pub fn reconciled_local_at(
  v : ReconciledContexts,
  i : Int,
) -> @local_inputs.ReconciledAttachment? {
  v.locals.get(i)
}

///|
pub fn reconciled_usage(v : ReconciledContexts) -> InputUsage {
  v.usage
}
