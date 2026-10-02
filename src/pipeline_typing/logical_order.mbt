///|
/// Conditional on successful execution of the retained producer and pipeline.
/// This is not a standalone publication or runtime validation certificate.
struct LogicalOrder {
  origin : Target
  producer : CheckedStep?
  imported : ProducedInput?
  predecessor : Target?
  completion : SortCompletion?
  key_order : @evidence.KeyedRelation?
  dependencies : Array[Target]
  publication : ResultPublication?
  tie_order : LogicalOrder?
}

///|
/// Ordered operand occurrences required by the originating operation.
pub fn order_dependency_count(order : LogicalOrder) -> Int {
  order.dependencies.length()
}

///|
/// Repeated operand targets remain separate occurrences, in operand order.
pub fn order_dependency_at(order : LogicalOrder, index : Int) -> Target? {
  order.dependencies.get(index)
}

///|
pub fn logical_order(p : CheckedPipeline, target : Target) -> LogicalOrder? {
  match target {
    Input(i) => p.input_orders.get(i).bind(v => v)
    Step(i) => p.logical_orders.get(i).bind(v => v)
  }
}

///|
pub fn order_origin(order : LogicalOrder) -> Target {
  order.origin
}

///|
/// A local step producer; imported input origins have no local producer step.
pub fn order_producer(order : LogicalOrder) -> CheckedStep? {
  order.producer
}

///|
/// The retained upstream owner for an input-origin order. Its targets belong
/// to producer_pipeline, never to the receiving pipeline.
pub fn order_input_producer(order : LogicalOrder) -> ProducedInput? {
  order.imported
}

///|
fn imported_orders(inputs : Array[ProducedInput?]) -> Array[LogicalOrder?] {
  Array::makei(inputs.length(), i => {
    inputs[i].bind(input => {
      if input.order is None {
        return None
      }
      Some({
        origin: Input(i),
        producer: None,
        imported: Some(input),
        predecessor: None,
        completion: None,
        key_order: None,
        dependencies: [],
        publication: None,
        tie_order: None,
      })
    })
  })
}

///|
/// Immediate preserving edge; inspect it in the originating pipeline.
pub fn order_predecessor(order : LogicalOrder) -> Target? {
  order.predecessor
}

///|
/// An internally completed order before take; components are ascending/nulls-last.
pub fn order_key_completion(order : LogicalOrder) -> @evidence.KeyedRelation? {
  order.key_order
}

///|
/// Conditional order available before this take's offset/count selection.
/// None means unresolved, never permission to consume provider return order.
pub fn take_order(p : CheckedPipeline, index : Int) -> LogicalOrder? {
  match p.steps.get(index) {
    Some({ operation: Unary(op), .. }) if @relation.operation(op) ==
      @relation.Take => p.logical_orders.get(index).bind(v => v)
    _ => None
  }
}

///|
fn derive_logical_orders(
  b : Budget,
  steps : Array[CheckedStep],
  input_keys : Array[@evidence.KeySet?],
  step_keys : Array[@evidence.KeySet?],
  input_orders : Array[LogicalOrder?],
  joins : Array[JoinEvidence?],
) -> (
  Array[LogicalOrder?],
  Array[SortCompletion?],
  Array[AnalyticPositionOrder?],
) raise Stop {
  let out : Array[LogicalOrder?] = []
  let lag_orders : Array[SortCompletion?] = []
  let analytic_orders : Array[AnalyticPositionOrder?] = []
  for i in 0..<steps.length() {
    let step = steps[i]
    spend(b, step.source, 1)
    lag_orders.push(
      match step.operation {
        Unary(op) if @relation.operation(op) == @relation.Lag =>
          complete_sort(
            b,
            op,
            step.input.bind(t => key_at(t, input_keys, step_keys)),
          )
        _ => None
      },
    )
    let completion = match step.operation {
      Unary(op) if @relation.ranking_term_count(op) > 0 =>
        complete_sort(
          b,
          op,
          step.input.bind(t => key_at(t, input_keys, step_keys)),
        )
      _ => None
    }
    let previous = step.input.bind(t => {
      match t {
        Input(j) => input_orders[j]
        Step(j) => out[j]
      }
    })
    let tie_order = match step.operation {
      Unary(op) if @relation.operation(op) == @relation.Sort &&
        @relation.sort_term_count(op) > 0 &&
        completion is None => previous
      _ => None
    }
    let key_order = match step.operation {
      Unary(op) if @relation.operation(op) == @relation.Take && previous is None =>
        select_order_key(
          b,
          op,
          step.input.bind(t => key_at(t, input_keys, step_keys)),
        )
      _ => None
    }
    analytic_orders.push(
      match (step.operation, step.input) {
        (Unary(op), Some(input)) if @relation.operation(op) ==
          @relation.Analytic => {
          let completion = complete_sort(
            b,
            op,
            key_at(input, input_keys, step_keys),
          )
          if completion is Some(_) || previous is Some(_) {
            Some({
              consumer: step,
              input,
              completion,
              retained: if completion is Some(_) {
                None
              } else {
                previous
              },
            })
          } else {
            None
          }
        }
        _ => None
      },
    )
    let preserve = match step.operation {
      Unary(op) => @relation.preserves_input_order(op)
      Calendar(op) => @calendar.input(op) is Some(_)
      Event(op) =>
        match @event.options(op) {
          ToEvents | Watermark(_, _) => true
          _ => false
        }
      Projection(op) =>
        @projection.operation(op) == @projection.Events ||
        @projection.operation(op) == @projection.Vectors
      Vector(op) =>
        match @vector.operation(op) {
          ToVectors | NormalizeVectors => true
          ScoreVectors => false
        }
      Set(..) | Nest(..) => true
      _ => false
    }
    let establishes = match step.operation {
      // Model completion order is irrelevant. The acquisition owner must emit
      // captured outcomes in canonical typed key order.
      Infer(_)
      | Values(_)
      | TimeSeries(_)
      | Nearest(..)
      | Ranking(_)
      | TextRank(..)
      | AsOfJoin(..) => true
      Pool(_) => true
      GraphMatch(_) | Traverse(..) | Shortest(..) => true
      Graph(op) =>
        @graph.operation(op) == @graph.Components ||
        @graph.operation(op) == @graph.GraphBounds
      Vector(op) => @vector.operation(op) == @vector.ScoreVectors
      Unary(op) | WindowGroup(op) =>
        match @relation.operation(op) {
          Group | DedupeRows => true
          Pivot => !@relation.pivot_uses_first_occurrence(op)
          _ => false
        }
      Event(op) =>
        match @event.options(op) {
          Session(_) | Dedupe(_) => true
          _ => false
        }
      Sequence(_) => true
      Calendar(op) => @calendar.input(op) is None
      _ => false
    }
    let dependencies = match step.operation {
      Unary(op) if @relation.operation(op) == @relation.Sort &&
        tie_order is Some(_) => [step.input.unwrap()]
      Join(right~, checked~) => {
        let left_only = match @join.kind(checked) {
          Semi | Anti => true
          Inner | Left => join_uniqueness(joins[i].unwrap()).1
          _ => false
        }
        let right_order = match right {
          Input(j) => input_orders[j]
          Step(j) => out[j]
        }
        match (step.input, previous) {
          (Some(left), Some(_)) =>
            if left_only {
              [left]
            } else if right_order is Some(_) {
              [left, right]
            } else {
              []
            }
          _ => []
        }
      }
      // Existence/absence selects each left occurrence at most once. Endpoint,
      // coverage and search checks still belong to the complete binary producer;
      // only its right-hand order is unnecessary for enumeration.
      IntervalJoin(checked~, ..) if @join.interval_kind(checked) is Semi ||
        @join.interval_kind(checked) is Anti ||
        joins[i].unwrap().right is Some(_) =>
        match (step.input, previous) {
          (Some(left), Some(_)) => [left]
          _ => []
        }
      CrossJoin(checked~, ..) if @join.cross_requires_one_right_row(checked) =>
        match (step.input, previous) {
          (Some(left), Some(_)) => [left]
          _ => []
        }
      Append(right~, ..) | CrossJoin(right~, ..) | IntervalJoin(right~, ..) => {
        let right_order = match right {
          Input(j) => input_orders[j]
          Step(j) => out[j]
        }
        match (step.input, previous, right_order) {
          (Some(left), Some(_), Some(_)) => [left, right]
          _ => []
        }
      }
      Unary(op) if @relation.operation(op) == @relation.Unnest ||
        @relation.operation(op) == @relation.Unpivot ||
        @relation.pivot_uses_first_occurrence(op) =>
        match (step.input, previous) {
          (Some(input), Some(_)) => [input]
          _ => []
        }
      Window(_) =>
        match (step.input, previous) {
          (Some(input), Some(_)) => [input]
          _ => []
        }
      _ => []
    }
    out.push(
      if establishes ||
        completion is Some(_) ||
        key_order is Some(_) ||
        !dependencies.is_empty() {
        Some({
          origin: Step(i),
          producer: Some(step),
          imported: None,
          predecessor: None,
          completion,
          key_order,
          dependencies,
          publication: None,
          tie_order,
        })
      } else if preserve {
        previous.map(v => { ..v, predecessor: step.input, })
      } else {
        None
      },
    )
  }
  (out, lag_orders, analytic_orders)
}

///|
/// Conditional partition-order completion for lag, never output row ordering.
/// The originating pipeline retains the lag operation and its input edge.
pub fn lag_order_completion(
  p : CheckedPipeline,
  index : Int,
) -> SortCompletion? {
  p.lag_orders.get(index).bind(v => v)
}
