///|
pub(all) enum ExpressionConsumer {
  DerivedField(String, Int?)
  RowFilter
  RowAssertion
  AggregateFilter(String)
  AggregateArgument(String)
  AnalyticFilter(String)
  AnalyticArgument(String)
  SequencePredicate(Int)
  GraphMatchPredicate
  GraphTraverseEdgePredicate(Int)
  GraphTraverseNodePredicate(Int)
  InferInput(Int)
} derive(Eq, Debug)

///|
/// An earlier root in the same owning slot collection, not a caller predicate.
pub struct ExpressionFilter {
  slot : Int
  expression : @typing.TypedExpression
}

///|
pub struct ExpressionSlot {
  step : Int
  expression : @typing.TypedExpression
  consumer : ExpressionConsumer
  filter : ExpressionFilter?
}

///|
struct ExpressionSlots {
  pipeline : CheckedPipeline
  entries : Array[ExpressionSlot]
  work : Int
}

///|
pub(all) enum ExpressionSlotIssue {
  InvalidLimits
  WorkLimit
  SlotLimit
  InvalidBindings(Int)
} derive(Eq, Debug)

///|
priv struct SlotCollector {
  entries : Array[ExpressionSlot]
  mut remaining : Int
  max_slots : Int
}

///|
priv suberror SlotFailure {
  SlotFailure(ExpressionSlotIssue)
}

///|
fn slot_tick(c : SlotCollector) -> Unit raise SlotFailure {
  if c.remaining == 0 {
    raise SlotFailure(WorkLimit)
  }
  c.remaining -= 1
}

///|
fn slot_add(
  c : SlotCollector,
  step : Int,
  expression : @typing.TypedExpression?,
  consumer : ExpressionConsumer,
  filter? : ExpressionFilter? = None,
) -> Unit raise SlotFailure {
  slot_tick(c)
  if expression is Some(expression) {
    if c.entries.length() == c.max_slots {
      raise SlotFailure(SlotLimit)
    }
    c.entries.push({ step, expression, consumer, filter, })
  }
}

///|
fn slot_predicate(
  c : SlotCollector,
  step : Int,
  predicate : @graph.CheckedPredicate?,
  consumer : ExpressionConsumer,
) -> Unit raise SlotFailure {
  slot_add(c, step, predicate.map(@graph.predicate_expression), consumer)
}

///|
fn slot_aggregate(
  c : SlotCollector,
  step : Int,
  operation : @relation.CheckedOperation,
  aggregate : @relation.CheckedAggregate,
  analytic : Bool,
) -> Unit raise SlotFailure {
  slot_tick(c)
  let name = @relation.aggregate_name(aggregate)
  let filter = match @relation.aggregate_filter(aggregate) {
    None => None
    Some(index) => {
      let expression = @relation.binding_at(operation, index).unwrap().expression
      let slot = c.entries.length()
      slot_add(
        c,
        step,
        Some(expression),
        if analytic {
          AnalyticFilter(name)
        } else {
          AggregateFilter(name)
        },
      )
      Some({ slot, expression, })
    }
  }
  if @relation.aggregate_argument(aggregate) is @relation.Expression(index) {
    slot_add(
      c,
      step,
      Some(@relation.binding_at(operation, index).unwrap().expression),
      if analytic {
        AnalyticArgument(name)
      } else {
        AggregateArgument(name)
      },
      filter~,
    )
  }
}

///|
fn slot_relation(
  c : SlotCollector,
  step : Int,
  operation : @relation.CheckedOperation,
) -> Unit raise SlotFailure {
  let before = c.entries.length()
  match @relation.operation(operation) {
    Derive | Filter | AssertRows =>
      for i in 0..<@relation.binding_count(operation) {
        let binding = @relation.binding_at(operation, i).unwrap()
        let consumer = match @relation.operation(operation) {
          Derive =>
            DerivedField(
              binding.name.unwrap(),
              if @relation.form(operation) is DeriveArray {
                Some(i)
              } else {
                None
              },
            )
          Filter => RowFilter
          _ => RowAssertion
        }
        slot_add(c, step, Some(binding.expression), consumer)
      }
    Group => {
      let group = @relation.group(operation).unwrap()
      for i in 0..<@relation.aggregate_count(group) {
        slot_aggregate(
          c,
          step,
          operation,
          @relation.aggregate_at(group, i).unwrap(),
          false,
        )
      }
    }
    Analytic => {
      let analytic = @relation.analytic(operation).unwrap()
      for i in 0..<@relation.analytic_call_count(analytic) {
        let call = @relation.analytic_call_at(analytic, i).unwrap()
        match call.function {
          @relation.Aggregate(aggregate) =>
            slot_aggregate(c, step, operation, aggregate, true)
          @relation.Lag(argument~, ..)
          | @relation.Lead(argument~, ..)
          | @relation.FirstValue(argument~)
          | @relation.LastValue(argument~) => {
            slot_tick(c)
            slot_add(
              c,
              step,
              Some(
                @relation.binding_at(operation, argument).unwrap().expression,
              ),
              AnalyticArgument(call.name),
            )
          }
          @relation.RowNumber | @relation.Rank | @relation.DenseRank =>
            slot_tick(c)
        }
      }
    }
    Select
    | Rename
    | Drop
    | Sort
    | Take
    | Distinct
    | DedupeRows
    | JsonPick
    | Unnest
    | Unpivot
    | Pivot
    | TopK
    | TopKBy
    | Lag
    | WatermarkRows => ()
  }
  if c.entries.length() - before != @relation.binding_count(operation) {
    raise SlotFailure(InvalidBindings(step))
  }
}

///|
/// Enumerate retained typed expression roots in every local step. This does not
/// include non-expression Parameter operands or recursively visit producers.
pub fn collect_expression_slots(
  pipeline : CheckedPipeline,
  max_work~ : Int,
  max_slots~ : Int,
) -> Result[ExpressionSlots, ExpressionSlotIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let c : SlotCollector = { entries: [], remaining: max_work, max_slots, }
  try {
    for step in 0..<pipeline.steps.length() {
      slot_tick(c)
      match pipeline.steps[step].operation {
        Infer(operation) =>
          for i in 0..<@evidence.infer_input_binding_count(operation) {
            let binding = @evidence.infer_input_binding_at(operation, i).unwrap()
            slot_add(c, step, Some(binding.expression), InferInput(i))
          }
        Unary(operation) | WindowGroup(operation) =>
          slot_relation(c, step, operation)
        Sequence(operation) =>
          for i in 0..<@relation.sequence_pattern_count(operation) {
            slot_add(
              c,
              step,
              Some(
                @relation.sequence_pattern_at(operation, i).unwrap().predicate,
              ),
              SequencePredicate(i),
            )
          }
        GraphMatch(operation) =>
          slot_predicate(
            c,
            step,
            @graph.match_predicate(operation),
            GraphMatchPredicate,
          )
        Traverse(checked~, ..) =>
          for i in 0..<@graph.traverse_hop_count(checked) {
            let hop = @graph.traverse_hop_at(checked, i).unwrap()
            slot_predicate(
              c,
              step,
              @graph.hop_edge_predicate(hop),
              GraphTraverseEdgePredicate(i),
            )
            slot_predicate(
              c,
              step,
              @graph.hop_node_predicate(hop),
              GraphTraverseNodePredicate(i),
            )
          }
        // These checked forms retain scalar/cell operands or field selectors,
        // not general Expression roots. Do not use a catch-all here.
        Join(..)
        | Append(..)
        | Nest(..)
        | Set(..)
        | CrossJoin(..)
        | IntervalJoin(..)
        | AsOfJoin(..)
        | Values(_)
        | TimeSeries(_)
        | Calendar(_)
        | Window(_)
        | Projection(_)
        | GraphBounds(_)
        | GraphDegree(_)
        | PropertyGraphConstruction(..)
        | Vector(_)
        | Nearest(..)
        | Pool(_)
        | Ranking(_)
        | TextRank(_)
        | Event(_) => ()
      }
    }
    Ok({ pipeline, entries: c.entries, work: max_work - c.remaining, })
  } catch {
    SlotFailure(issue) => Err(issue)
  }
}

///|
pub fn expression_slots_pipeline(slots : ExpressionSlots) -> CheckedPipeline {
  slots.pipeline
}

///|
pub fn expression_slot_count(slots : ExpressionSlots) -> Int {
  slots.entries.length()
}

///|
pub fn expression_slot_at(
  slots : ExpressionSlots,
  index : Int,
) -> ExpressionSlot? {
  slots.entries.get(index)
}

///|
pub fn expression_slots_work(slots : ExpressionSlots) -> Int {
  slots.work
}
