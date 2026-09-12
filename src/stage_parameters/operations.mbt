///|
pub(all) enum OperationsIssue {
  InvalidLimits
  PipelineCountMismatch
  ForeignStage(Int)
  WorkLimit
  Stage(Int, Issue)
  References(@references.Issue)
} derive(Eq, Debug)

///|
pub(all) struct OperationsUsage {
  work : Int
  slots : Int
  references : Int
  pointer_units : Int
  direct_text_bytes : Int
} derive(Eq, Debug)

///|
struct CollectedOperations {
  source : Source
  stages : Array[CollectedStage]
  index : @references.Index
  usage : OperationsUsage
}

///|
/// Collect every stage's currently admitted operation slots. Other Program
/// grammar slots remain outside this boundary and must not be assumed unused.
pub fn collect_operations(
  source : Source,
  pipelines : Array[@pipeline.CheckedPipeline],
  limits : @collection.Limits,
) -> Result[CollectedOperations, OperationsIssue] {
  assemble_operations(source, pipelines.length(), limits, (i, remaining) => {
    match collect(source, i, pipelines[i], remaining) {
      Err(e) => Err(Stage(i, e))
      Ok(v) => Ok(v)
    }
  })
}

///|
/// Preserve the exact source-bound stages already used for producer ports and
/// input evidence. Prior collection costs remain part of the aggregate budget.
pub fn collect_prepared_operations(
  source : Source,
  stages : Array[CollectedStage],
  limits : @collection.Limits,
) -> Result[CollectedOperations, OperationsIssue] {
  assemble_operations(source, stages.length(), limits, (i, _) => {
    let value = stages[i]
    if !physical_equal(value.source, source) || value.stage_index != i {
      Err(ForeignStage(i))
    } else {
      Ok(value)
    }
  })
}

///|
fn assemble_operations(
  source : Source,
  count : Int,
  limits : @collection.Limits,
  prepare : (Int, @collection.Limits) -> Result[CollectedStage, OperationsIssue],
) -> Result[CollectedOperations, OperationsIssue] {
  if limits.max_work < 0 ||
    limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 ||
    limits.max_direct_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if count != stage_count(source) {
    return Err(PipelineCountMismatch)
  }
  let mut remaining = limits
  let stages : Array[CollectedStage] = []
  let slots : Array[@expression.ParameterOccurrences] = []
  for i in 0..<count {
    if remaining.max_work == 0 {
      return Err(WorkLimit)
    }
    remaining = { ..remaining, max_work: remaining.max_work - 1, }
    let result = match prepare(i, remaining) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let local_collection = collection(result)
    let local_index = @collection.index(local_collection)
    let slot_count = @pipeline.expression_slot_count(
        @collection.expressions(local_collection),
      ) +
      @pipeline.parameter_slot_count(@collection.operands(local_collection))
    if collection_work(result) > remaining.max_work ||
      slot_count > remaining.max_slots ||
      @references.reference_count(local_index) > remaining.max_references ||
      @references.pointer_units(local_index) > remaining.max_pointer_units ||
      @collection.direct_text_bytes(local_collection) >
      remaining.max_direct_text_bytes {
      return Err(WorkLimit)
    }
    remaining = {
      max_work: remaining.max_work - collection_work(result),
      max_slots: remaining.max_slots - slot_count,
      max_references: remaining.max_references -
      @references.reference_count(local_index),
      max_pointer_units: remaining.max_pointer_units -
      @references.pointer_units(local_index),
      max_direct_text_bytes: remaining.max_direct_text_bytes -
      @collection.direct_text_bytes(local_collection),
    }
    // Charge handle gathering separately from the local collection's indexing.
    if slot_count > remaining.max_work {
      return Err(WorkLimit)
    }
    remaining = { ..remaining, max_work: remaining.max_work - slot_count, }
    for j in 0..<slot_count {
      slots.push(@references.slot_at(local_index, j).unwrap())
    }
    stages.push(result)
  }
  let reference_count = limits.max_references - remaining.max_references
  // Re-indexing in Program coordinates retains another set of records and paths.
  // Occurrences themselves are shared, not re-admitted or re-enumerated.
  if reference_count > remaining.max_work {
    return Err(WorkLimit)
  }
  remaining = { ..remaining, max_work: remaining.max_work - reference_count, }
  let index = match
    @references.build(
      @stage.program_body(source.program),
      source.declarations,
      slots,
      {
        max_slots: slots.length(),
        max_references: reference_count,
        max_pointer_units: if remaining.max_work < remaining.max_pointer_units {
          remaining.max_work
        } else {
          remaining.max_pointer_units
        },
      },
    ) {
    Err(e) => return Err(References(e))
    Ok(v) => v
  }
  let pointer_units = @references.pointer_units(index)
  Ok({
    source,
    stages,
    index,
    usage: {
      work: limits.max_work - remaining.max_work + pointer_units,
      slots: slots.length(),
      references: reference_count,
      pointer_units: limits.max_pointer_units -
      remaining.max_pointer_units +
      pointer_units,
      direct_text_bytes: limits.max_direct_text_bytes -
      remaining.max_direct_text_bytes,
    },
  })
}

///|
pub fn operations_source(value : CollectedOperations) -> Source {
  value.source
}

///|
pub fn operations_stage_at(
  value : CollectedOperations,
  index : Int,
) -> CollectedStage? {
  value.stages.get(index)
}

///|
pub fn operations_index(value : CollectedOperations) -> @references.Index {
  value.index
}

///|
pub fn operations_usage(value : CollectedOperations) -> OperationsUsage {
  value.usage
}
