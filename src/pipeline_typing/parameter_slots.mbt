///|
pub struct ParameterSlot {
  step : Int
  name : String
  source : @decode.Cursor
}

///|
struct ParameterSlots {
  pipeline : CheckedPipeline
  entries : Array[ParameterSlot]
  work : Int
}

///|
priv struct OperandCollector {
  entries : Array[ParameterSlot]
  mut remaining : Int
  max_slots : Int
}

///|
fn operand_tick(c : OperandCollector) -> Unit raise SlotFailure {
  if c.remaining == 0 {
    raise SlotFailure(WorkLimit)
  }
  c.remaining -= 1
}

///|
fn operand(
  c : OperandCollector,
  step : Int,
  source : @decode.Cursor,
) -> Unit raise SlotFailure {
  if @decode.object_length(source) == Some(1) {
    let (name, value) = @decode.field_at(source, 0).unwrap()
    if name == "$param" {
      if @decode.text(value) is Ok(name) {
        if c.entries.length() == c.max_slots {
          raise SlotFailure(SlotLimit)
        }
        c.entries.push({ step, name, source, })
      }
    }
  }
}

///|
// Inspect only immediate grammar fields, never generic JSON descendants.
fn operand_fields(
  c : OperandCollector,
  step : Int,
  source : @decode.Cursor,
  names : Array[String],
) -> Unit raise SlotFailure {
  if @decode.object_length(source) is Some(count) {
    for i in 0..<count {
      operand_tick(c)
      let (name, value) = @decode.field_at(source, i).unwrap()
      if names.contains(name) {
        operand(c, step, value)
      }
    }
  }
}

///|
fn aggregate_operands(
  c : OperandCollector,
  step : Int,
  aggregate : @relation.CheckedAggregate,
) -> Unit raise SlotFailure {
  operand_fields(c, step, @relation.aggregate_source(aggregate), [
    "max_items", "max_bytes", "fraction",
  ])
}

///|
fn relation_operands(
  c : OperandCollector,
  step : Int,
  op : @relation.CheckedOperation,
) -> Unit raise SlotFailure {
  let source = @relation.source(op)
  match @relation.operation(op) {
    Take => {
      operand_tick(c)
      operand(c, step, source)
      operand_fields(c, step, source, ["count", "offset"])
    }
    TopK | TopKBy => operand_fields(c, step, source, ["k"])
    Lag => operand_fields(c, step, source, ["offset"])
    WatermarkRows =>
      operand_fields(c, step, source, ["watermark_ms", "max_skew"])
    Pivot => operand_fields(c, step, source, ["fill"])
    Group => {
      let group = @relation.group(op).unwrap()
      for i in 0..<@relation.aggregate_count(group) {
        operand_tick(c)
        aggregate_operands(c, step, @relation.aggregate_at(group, i).unwrap())
      }
    }
    Analytic => {
      let analytic = @relation.analytic(op).unwrap()
      for i in 0..<@relation.analytic_call_count(analytic) {
        operand_tick(c)
        let call = @relation.analytic_call_at(analytic, i).unwrap()
        operand_fields(c, step, call.source, ["offset"])
        if call.function is Aggregate(aggregate) {
          aggregate_operands(c, step, aggregate)
        }
      }
      if @relation.analytic_frame(analytic) is Some(frame) {
        let fields = @decode.open_object(frame.source).unwrap()
        for name in ["start", "end"] {
          operand_tick(c)
          operand_fields(c, step, @decode.lookup(fields, name).unwrap(), [
            "preceding", "following",
          ])
        }
      }
    }
    Derive
    | Filter
    | Select
    | Rename
    | Drop
    | Sort
    | Distinct
    | DedupeRows
    | JsonPick
    | Unnest
    | AssertRows
    | Unpivot => ()
  }
}

///|
/// Collect currently admitted non-expression Parameter operands. Expression
/// roots are handled separately; literal payloads and annotations stay opaque.
pub fn collect_parameter_slots(
  pipeline : CheckedPipeline,
  max_work~ : Int,
  max_slots~ : Int,
) -> Result[ParameterSlots, ExpressionSlotIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let c : OperandCollector = { entries: [], remaining: max_work, max_slots, }
  try {
    for step in 0..<pipeline.steps.length() {
      operand_tick(c)
      match pipeline.steps[step].operation {
        Infer(operation) =>
          operand_fields(c, step, @evidence.infer_source(operation), [
            "max_items",
          ])
        Unary(op) | WindowGroup(op) => relation_operands(c, step, op)
        Join(checked~, ..) =>
          operand_fields(c, step, @join.source(checked), ["max_output_rows"])
        CrossJoin(checked~, ..) =>
          operand_fields(c, step, @join.cross_source(checked), [
            "max_output_rows",
          ])
        IntervalJoin(checked~, ..) =>
          operand_fields(c, step, @join.interval_source(checked), [
            "max_output_rows",
          ])
        AsOfJoin(checked~, ..) =>
          operand_fields(c, step, @join.asof_source(checked), ["tolerance"])
        Nest(checked~, ..) =>
          operand_fields(c, step, @nest.source(checked), ["max_items"])
        Sequence(op) =>
          operand_fields(c, step, @relation.sequence_source(op), [
            "within", "max_matches_per_key", "max_output_rows",
          ])
        Window(op) =>
          operand_fields(c, step, @window.source(op), ["size", "step", "offset"])
        Event(op) =>
          operand_fields(c, step, @event.source(op), [
            "gap", "watermark_ms", "max_skew",
          ])
        TimeSeries(op) =>
          operand_fields(c, step, @series.source(op), ["start", "end", "step"])
        Calendar(op) =>
          operand_fields(c, step, @calendar.source(op), ["start", "end"])
        Traverse(checked~, ..) =>
          operand_fields(c, step, @graph.traverse_source(checked), [
            "max_output_rows",
          ])
        GraphBounds(checked) =>
          operand_fields(c, step, @graph.graph_bounds_source(checked), [
            "max_nodes", "max_edges", "max_degree",
          ])
        GraphComponents(checked) =>
          operand_fields(c, step, @graph.components_source(checked), [
            "max_output_rows",
          ])
        Vector(op) => operand_fields(c, step, @vector.source(op), ["query"])
        Values(op) =>
          for i in 0..<@values.row_count(op) {
            operand_tick(c)
            let row = @values.row_at(op, i).unwrap()
            let count = @decode.object_length(@values.row_source(row)).unwrap()
            for j in 0..<count {
              operand_tick(c)
              if @values.cell_at(row, j).unwrap() is Parameter(_, source~, ..) {
                operand(c, step, source)
              }
            }
          }
        Append(..)
        | Set(..)
        | Projection(_)
        | GraphMatch(_)
        | Subgraph(..)
        | GraphDegree(_)
        | GraphEquality(..)
        | GraphNormalize(_)
        | GraphDelta(..)
        | GraphUnion(..)
        | PropertyGraphConstruction(..)
        | Nearest(..)
        | Pool(_)
        | Ranking(_)
        | TextRank(_) => ()
      }
    }
    Ok({ pipeline, entries: c.entries, work: max_work - c.remaining, })
  } catch {
    SlotFailure(issue) => Err(issue)
  }
}

///|
pub fn parameter_slots_pipeline(slots : ParameterSlots) -> CheckedPipeline {
  slots.pipeline
}

///|
pub fn parameter_slot_count(slots : ParameterSlots) -> Int {
  slots.entries.length()
}

///|
pub fn parameter_slot_at(slots : ParameterSlots, index : Int) -> ParameterSlot? {
  slots.entries.get(index)
}

///|
pub fn parameter_slots_work(slots : ParameterSlots) -> Int {
  slots.work
}
