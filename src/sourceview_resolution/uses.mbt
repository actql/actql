///|
pub(all) enum UseIssue {
  InvalidLimits
  WorkLimit
  ForeignResults
} derive(Eq, Debug)

///|
/// A syntactic consumer position, not a selected acquisition strategy.
pub(all) enum SourceUse {
  StepInput(Int, @pipeline.InputRole)
  JoinRight(Int)
  ResultInput(Int)
} derive(Eq, Debug)

///|
struct PipelineUses {
  attachment : PipelineAttachment
  results : @stage_results.Checked
  entries : Array[Array[SourceUse]]
  work : Int
}

///|
/// Enumerate every operation edge and Result reference against the actual stage.
/// Work covers this pass only; retained prerequisites keep their own usage.
pub fn collect_pipeline_uses(
  attachment : PipelineAttachment,
  results : @stage_results.Checked,
  max_work : Int,
) -> Result[PipelineUses, UseIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let stage = attachment.stage
  let index = @stages.stage_index(stage)
  guard @stages.operations_stage_at(@stage_results.operations(results), index)
    is Some(owner) &&
    physical_equal(owner, stage) else {
    return Err(ForeignResults)
  }
  let pipeline = @collection.pipeline(@stages.collection(stage))
  let definitions = @stage_results.stage_at(results, index).unwrap()
  let inputs = attachment.inputs.stages[index]
  let n = @pipeline.input_count(pipeline)
  let mut remaining = max_work
  for cost in [1, n, inputs.length()] {
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
  }
  let entries : Array[Array[SourceUse]] = Array::makei(inputs.length(), _ => [])
  let names : Map[String, Int] = Map([])
  for i in 0..<inputs.length() {
    let name = inputs[i].input.declaration.input_name
    if name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= name.length()
    names[name] = i
  }
  let positions : Array[Int?] = Array::makei(n, _ => None)
  for i in 0..<n {
    let name = @pipeline.input_at(pipeline, i).unwrap().0
    if name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= name.length()
    positions[i] = names.get(name)
  }
  for i in 0..<@pipeline.step_count(pipeline) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let step = @pipeline.step_at(pipeline, i).unwrap()
    for j in 0..<@pipeline.input_occurrence_count(step) {
      if remaining == 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      let occurrence = @pipeline.input_occurrence_at(step, j).unwrap()
      if occurrence.target is @pipeline.Input(input) &&
        positions[input] is Some(slot) {
        let consumer = if step.operation is @pipeline.Join(..) &&
          occurrence.role == @pipeline.Right {
          JoinRight(i)
        } else {
          StepInput(i, occurrence.role)
        }
        entries[slot].push(consumer)
      }
    }
  }
  for i in 0..<@results.count(definitions) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let definition = @results.result_at(definitions, i).unwrap()
    if @results.target(definition) is @pipeline.Input(input) &&
      positions[input] is Some(slot) {
      entries[slot].push(ResultInput(i))
    }
  }
  Ok({ attachment, results, entries, work: max_work - remaining, })
}

///|
pub fn pipeline_uses_attachment(v : PipelineUses) -> PipelineAttachment {
  v.attachment
}

///|
pub fn pipeline_uses_results(v : PipelineUses) -> @stage_results.Checked {
  v.results
}

///|
pub fn pipeline_uses_work(v : PipelineUses) -> Int {
  v.work
}

///|
pub fn pipeline_use_count(v : PipelineUses, input : Int) -> Int? {
  v.entries.get(input).map(xs => xs.length())
}

///|
pub fn pipeline_use_at(
  v : PipelineUses,
  input : Int,
  occurrence : Int,
) -> SourceUse? {
  v.entries.get(input).bind(xs => xs.get(occurrence))
}
