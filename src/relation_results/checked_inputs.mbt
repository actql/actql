///|
// Shared by strict publication ports and check-only dependency projections.
fn check_result_projection(
  results : CheckedResults,
  index : Int,
  limits : PortLimits,
) -> Result[(@relation.CheckedOperation, Usage), PortIssue] {
  let definition = results.definitions[index]
  let object = @decode.open_object(definition.source).unwrap()
  let fields = @decode.required(object, "fields").unwrap()
  let schema = @pipeline.schema_at(results.pipeline, definition.target).unwrap()
  let projection = match
    @relation.check(Select, fields, schema, None, {
      max_work: limits.max_work,
      max_nodes: limits.max_nodes,
      max_text_bytes: limits.max_text_bytes,
      max_tokens: 0,
      max_depth: limits.max_depth,
    }) {
    Err(e) => return Err(Projection(index, e))
    Ok(v) => v
  }
  Ok(
    (
      projection,
      {
        work: @relation.work_used(projection),
        nodes: @relation.nodes_used(projection),
        text_bytes: @relation.text_bytes_used(projection),
      },
    ),
  )
}

///|
struct CheckedResultInputs {
  results : CheckedResults
  inputs : Array[@pipeline.ProducedInput]
  usage : Usage
}

///|
/// Project checked Result declarations without resolving publication order.
/// The inputs retain their original producer and logical order, not a Result
/// publication or runtime port. All Result order obligations remain pending.
pub fn prepare_checked_inputs(
  results : CheckedResults,
  limits : PortLimits,
) -> Result[CheckedResultInputs, PortIssue] {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if results.definitions.length() > limits.max_results {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  let inputs = []
  for i in 0..<results.definitions.length() {
    if work == 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    let (projection, used) = match
      check_result_projection(results, i, {
        ..limits,
        max_work: work,
        max_nodes: nodes,
        max_text_bytes: text,
      }) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
    let projected = match
      @pipeline.project_produced_input(
        results.pipeline,
        results.definitions[i].target,
        projection,
        {
          max_steps: 0,
          max_work: work,
          max_nodes: nodes,
          max_text_bytes: text,
          max_tokens: 0,
          max_depth: limits.max_depth,
        },
      ) {
      Err(e) => return Err(Transfer(i, e))
      Ok(v) => v
    }
    let used = @pipeline.projected_input_usage(projected)
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
    inputs.push(@pipeline.projected_input(projected))
  }
  Ok({
    results,
    inputs,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn checked_inputs_results(value : CheckedResultInputs) -> CheckedResults {
  value.results
}

///|
pub fn checked_inputs_usage(value : CheckedResultInputs) -> Usage {
  value.usage
}

///|
pub fn checked_input_at(
  value : CheckedResultInputs,
  index : Int,
) -> @pipeline.ProducedInput? {
  value.inputs.get(index)
}

///|
pub fn lookup_checked_input(
  value : CheckedResultInputs,
  name : String,
) -> @pipeline.ProducedInput? {
  value.results.names.get(name).map(i => value.inputs[i])
}
