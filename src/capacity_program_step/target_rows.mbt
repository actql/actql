///|
pub(all) enum TargetRowsIssue {
  InvalidLimits
  InvalidTarget
  WrongUnit
  WorkLimit
  MissingProducer
  UnrelatedBound
} derive(Eq, Debug)

///|
struct TargetRows {
  pipeline : @pipeline.CheckedPipeline
  target : @pipeline.Target
  bound : StepBound
  work : Int
}

///|
/// Attach a checked producer's row upper bound to an actual pipeline target.
/// Does not discharge producer obligations or substitute a Host ceiling.
pub fn check_target_rows(
  pipeline : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  bound : StepBound,
  max_work : Int,
) -> Result[TargetRows, TargetRowsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if @wire.unit(@wire.program_proof_witness(bound.proof)) != @arithmetic.Rows {
    return Err(WrongUnit)
  }
  let mut owner = pipeline
  let mut current = target
  let mut work = 0
  while true {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work += 1
    match current {
      @pipeline.Step(i) => {
        let step = match @pipeline.step_at(owner, i) {
          Some(v) => v
          None => return Err(InvalidTarget)
        }
        if physical_equal(owner, bound.pipeline) && i == bound.index {
          break
        }
        current = match forwarded_input(step, @arithmetic.Rows) {
          Some(v) => v
          None => return Err(UnrelatedBound)
        }
      }
      @pipeline.Input(i) => {
        if @pipeline.input_at(owner, i) is None {
          return Err(InvalidTarget)
        }
        let producer = match @pipeline.input_producer(owner, i) {
          Some(v) => v
          None => return Err(MissingProducer)
        }
        owner = @pipeline.producer_pipeline(producer)
        current = @pipeline.producer_target(producer)
      }
    }
  }
  Ok({ pipeline, target, bound, work, })
}

///|
pub fn target_rows_pipeline(v : TargetRows) -> @pipeline.CheckedPipeline {
  v.pipeline
}

///|
pub fn target_rows_target(v : TargetRows) -> @pipeline.Target {
  v.target
}

///|
pub fn target_rows_bound(v : TargetRows) -> StepBound {
  v.bound
}

///|
pub fn target_rows_value(v : TargetRows) -> Int64 {
  @wire.value(@wire.program_proof_witness(v.bound.proof))
}

///|
pub fn target_rows_work(v : TargetRows) -> Int {
  v.work
}
