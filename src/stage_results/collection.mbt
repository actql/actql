///|
pub(all) struct CollectionLimits {
  max_results : Int
  max_work : Int
  max_nodes : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum CollectionIssue {
  InvalidLimits
  StageCountMismatch
  ForeignPipeline(Int)
  ForeignResults(Int)
  ForeignTableInputs(Int)
  BudgetExceeded(Int)
} derive(Eq, Debug)

///|
/// Retain previously checked stage Results used to prepare producer ports.
/// Exact source/pipeline correspondence is checked without reissuing Result
/// owners. Limits include earlier collection and Result-admission costs;
/// depth admission belongs to the earlier Result checker.
pub fn collect_checked(
  operations : @parameters.CollectedOperations,
  stages : Array[@results.CheckedResults],
  limits : CollectionLimits,
  table_inputs? : Array[@results.CheckedTableInputs?]? = None,
) -> Result[Checked, CollectionIssue] {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let source = @parameters.operations_source(operations)
  if stages.length() != @parameters.stage_count(source) {
    return Err(StageCountMismatch)
  }
  if table_inputs is Some(inputs) && inputs.length() != stages.length() {
    return Err(StageCountMismatch)
  }
  let prior = @parameters.operations_usage(operations).work
  if prior > limits.max_work {
    return Err(BudgetExceeded(0))
  }
  let mut left = { ..limits, max_work: limits.max_work - prior, }
  let owned : Array[@results.CheckedResults] = []
  let retained_inputs : Array[@results.CheckedTableInputs?] = []
  for i in 0..<stages.length() {
    if left.max_work == 0 {
      return Err(BudgetExceeded(i))
    }
    left = { ..left, max_work: left.max_work - 1, }
    let checked = stages[i]
    let stage = @parameters.operations_stage_at(operations, i).unwrap()
    if !physical_equal(
        @results.pipeline(checked),
        @collection.pipeline(@parameters.collection(stage)),
      ) {
      return Err(ForeignPipeline(i))
    }
    let body = @decode.open_object(
      @syntax.stage_body(@parameters.stage_at(source, i).unwrap()),
    ).unwrap()
    let expected = @decode.required(body, "results").unwrap()
    if @decode.tree_index(expected, @results.source(checked)) !=
      @decode.tree_index(expected, expected) {
      return Err(ForeignResults(i))
    }
    let usage = @results.usage(checked)
    let count = @results.count(checked)
    if usage.work > left.max_work ||
      usage.nodes > left.max_nodes ||
      usage.text_bytes > left.max_text_bytes ||
      count > left.max_results {
      return Err(BudgetExceeded(i))
    }
    left = {
      max_work: left.max_work - usage.work,
      max_nodes: left.max_nodes - usage.nodes,
      max_text_bytes: left.max_text_bytes - usage.text_bytes,
      max_results: left.max_results - count,
    }
    owned.push(checked)
    let inputs = table_inputs.bind(inputs => inputs.get(i).bind(input => input))
    match (@decode.lookup(body, "table_inputs"), inputs) {
      (None, None) => ()
      (Some(expected), Some(inputs)) => {
        if !physical_equal(
            @results.table_inputs_pipeline(inputs),
            @results.pipeline(checked),
          ) ||
          @decode.tree_index(expected, @results.table_inputs_source(inputs)) !=
          @decode.tree_index(expected, expected) {
          return Err(ForeignTableInputs(i))
        }
        let used = @results.table_inputs_usage(inputs)
        let count = @results.table_input_count(inputs)
        if used.work > left.max_work ||
          used.nodes > left.max_nodes ||
          used.text_bytes > left.max_text_bytes ||
          count > left.max_results {
          return Err(BudgetExceeded(i))
        }
        left = {
          max_work: left.max_work - used.work,
          max_nodes: left.max_nodes - used.nodes,
          max_text_bytes: left.max_text_bytes - used.text_bytes,
          max_results: left.max_results - count,
        }
      }
      _ => return Err(ForeignTableInputs(i))
    }
    retained_inputs.push(inputs)
  }
  Ok({
    operations,
    stages: owned,
    table_inputs: retained_inputs,
    usage: {
      work: limits.max_work - left.max_work,
      nodes: limits.max_nodes - left.max_nodes,
      text_bytes: limits.max_text_bytes - left.max_text_bytes,
      results: limits.max_results - left.max_results,
    },
  })
}
