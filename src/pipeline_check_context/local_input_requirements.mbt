///|
/// These are requirements on future materialization, not admitted input values.
pub(all) enum LocalInputDisposition {
  RejectDuplicatesAdmission
  DuplicateOrderUnresolved
} derive(Eq, Debug)

///|
/// Exact source declaration, selected schema evidence and pipeline registration.
/// Admission must validate all raw known fields and key components, never only
/// surviving rows. Key uniqueness and classification remain data checks.
pub struct LocalInputRequirement {
  stage : Int
  declaration_index : Int
  name : String
  pipeline : @pipeline.CheckedPipeline
  target : @pipeline.Target
  declaration : @local_input.Checked
  registration : @pipeline.InputContract
  attachment : @local_inputs.ReconciledAttachment
  disposition : LocalInputDisposition
}

///|
priv suberror LocalInputRequirementStop {
  Stop(IncomingLinksIssue)
}

///|
fn collect_local_input_requirements(
  context : ReconciledContexts,
  max_work : Int,
) -> (Array[LocalInputRequirement], Int) raise LocalInputRequirementStop {
  let out = []
  let mut remaining = max_work
  for stage in 0..<context.locals.length() {
    if remaining == 0 {
      raise Stop(BudgetExceeded)
    }
    remaining -= 1
    let attachment = context.locals[stage]
    let collected = @local_inputs.reconciled_stage(attachment)
    let pipeline = @parameter_slots.pipeline(@stages.collection(collected))
    let inputs = @local_inputs.reconciled_inputs(attachment)
    let prepared = @local_inputs.snapshot_inputs(
      @local_inputs.environment_assertions(inputs),
    )
    let count = @local_inputs.count(prepared)
    if count > remaining {
      raise Stop(BudgetExceeded)
    }
    remaining -= count
    for index in 0..<count {
      let (name, declaration) = @local_inputs.entry_at(prepared, index).unwrap()
      if name.length() > remaining {
        raise Stop(BudgetExceeded)
      }
      remaining -= name.length()
      guard @pipeline.lookup(pipeline, name) is Some(target) else {
        raise Stop(LocalInputOwner(stage, index))
      }
      guard target is @pipeline.Input(at) else {
        raise Stop(LocalInputOwner(stage, index))
      }
      guard @pipeline.input_contract_at(pipeline, at) is Some(registration) else {
        raise Stop(LocalInputOwner(stage, index))
      }
      out.push({
        stage,
        declaration_index: index,
        name,
        pipeline,
        target,
        declaration,
        registration,
        attachment,
        disposition: if @local_input.has_first_by_order(declaration) {
          DuplicateOrderUnresolved
        } else {
          RejectDuplicatesAdmission
        },
      })
    }
  }
  (out, max_work - remaining)
}
