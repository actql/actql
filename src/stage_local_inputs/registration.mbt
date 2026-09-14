///|
struct ReconciledAttachment {
  inputs : EnvironmentInputs
  stage : @stages.CollectedStage
  work : Int
}

///|
/// Select known schema evidence before pipeline checking. Missing evidence
/// retains the source contract; conditional keys remain conditional.
pub fn environment_input_at(
  value : EnvironmentInputs,
  index : Int,
) -> (String, @pipeline.InputContract)? {
  value.registrations.get(index)
}

///|
fn reconciled_input_at(
  checked : CheckedSnapshots,
  index : Int,
) -> (String, @pipeline.InputContract)? {
  let prepared = snapshot_inputs(checked)
  let entry = match prepared.entries.get(index) {
    Some(v) => v
    None => return None
  }
  match schema_agreement_at(snapshot_assertions(checked), index) {
    None => input_at(prepared, index)
    Some(agreement) =>
      Some(
        (
          entry.0,
          match @local_input.schema_primary_key(agreement) {
            Some(key) => @pipeline.KeyedInput(key)
            None =>
              @pipeline.CarrierInput(@local_input.schema_carrier(agreement))
          },
        ),
      )
  }
}

///|
/// Link exactly the registrations used to check this pipeline. This is typed
/// source/evidence linkage, not authenticated Host admission or execution.
pub fn attach_reconciled(
  inputs : EnvironmentInputs,
  stage : @stages.CollectedStage,
  max_work~ : Int,
) -> Result[ReconciledAttachment, Issue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let prepared = snapshot_inputs(environment_assertions(inputs))
  if !physical_equal(prepared.source, @stages.source(stage)) ||
    prepared.stage != @stages.stage_index(stage) {
    return Err(ForeignStage)
  }
  let mut remaining = max_work
  for cost in [environment_usage(inputs).work, @stages.collection_work(stage)] {
    if cost > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= cost
  }
  let pipeline = @collection.pipeline(@stages.collection(stage))
  let count = @pipeline.input_count(pipeline)
  if count > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= count
  let registered : Map[String, Int] = Map([])
  for i in 0..<count {
    registered[@pipeline.input_at(pipeline, i).unwrap().0] = i
  }
  for i in 0..<prepared.entries.length() {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    let (name, expected) = environment_input_at(inputs, i).unwrap()
    let index = match registered.get(name) {
      Some(v) => v
      None => return Err(ForeignInput(name))
    }
    let actual = @pipeline.input_contract_at(pipeline, index).unwrap()
    let same = match (expected, actual) {
      (@pipeline.KeyedInput(a), @pipeline.KeyedInput(b)) => physical_equal(a, b)
      (@pipeline.CarrierInput(a), @pipeline.CarrierInput(b)) =>
        physical_equal(a, b)
      (@pipeline.RankingInput(a), @pipeline.RankingInput(b)) =>
        physical_equal(a, b)
      (@pipeline.RelationEvidenceInput(a), @pipeline.RelationEvidenceInput(b)) =>
        physical_equal(a, b)
      _ => false
    }
    if !same {
      return Err(ForeignInput(name))
    }
  }
  Ok({ inputs, stage, work: max_work - remaining, })
}

///|
pub fn reconciled_inputs(v : ReconciledAttachment) -> EnvironmentInputs {
  v.inputs
}

///|
pub fn reconciled_stage(v : ReconciledAttachment) -> @stages.CollectedStage {
  v.stage
}

///|
pub fn reconciled_work(v : ReconciledAttachment) -> Int {
  v.work
}
