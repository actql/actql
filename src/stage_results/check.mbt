///|
pub enum Issue {
  InvalidLimits
  WorkLimit
  Stage(Int, @results.Issue)
}

///|
pub(all) struct Usage {
  work : Int
  results : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct Checked {
  operations : @parameters.CollectedOperations
  stages : Array[@results.CheckedResults]
  usage : Usage
}

///|
/// Check actual stage Result bodies against their source-bound pipelines.
/// Work includes the already collected operation references; other limits here
/// cover Result admission only. Publication evidence remains unresolved.
pub fn check(
  operations : @parameters.CollectedOperations,
  limits : @results.Limits,
) -> Result[Checked, Issue] {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let prior_work = @parameters.operations_usage(operations).work
  if prior_work > limits.max_work {
    return Err(WorkLimit)
  }
  let mut remaining = { ..limits, max_work: limits.max_work - prior_work, }
  let source = @parameters.operations_source(operations)
  let stages : Array[@results.CheckedResults] = []
  for i in 0..<@parameters.stage_count(source) {
    if remaining.max_work == 0 {
      return Err(WorkLimit)
    }
    remaining = { ..remaining, max_work: remaining.max_work - 1, }
    let stage = @parameters.stage_at(source, i).unwrap()
    let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
    let pipeline = @collection.pipeline(
      @parameters.collection(
        @parameters.operations_stage_at(operations, i).unwrap(),
      ),
    )
    let checked = match
      @results.check(
        pipeline,
        @decode.required(body, "results").unwrap(),
        remaining,
      ) {
      Err(e) => return Err(Stage(i, e))
      Ok(v) => v
    }
    let usage = @results.usage(checked)
    remaining = {
      ..remaining,
      max_work: remaining.max_work - usage.work,
      max_results: remaining.max_results - @results.count(checked),
      max_nodes: remaining.max_nodes - usage.nodes,
      max_text_bytes: remaining.max_text_bytes - usage.text_bytes,
    }
    stages.push(checked)
  }
  Ok({
    operations,
    stages,
    usage: {
      work: limits.max_work - remaining.max_work,
      results: limits.max_results - remaining.max_results,
      nodes: limits.max_nodes - remaining.max_nodes,
      text_bytes: limits.max_text_bytes - remaining.max_text_bytes,
    },
  })
}

///|
pub fn operations(value : Checked) -> @parameters.CollectedOperations {
  value.operations
}

///|
pub fn stage_at(value : Checked, index : Int) -> @results.CheckedResults? {
  value.stages.get(index)
}

///|
pub fn usage(value : Checked) -> Usage {
  value.usage
}
