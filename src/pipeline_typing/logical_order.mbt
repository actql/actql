///|
/// Conditional on successful execution of the retained producer and pipeline.
/// This is not a standalone publication or runtime validation certificate.
struct LogicalOrder {
  origin : Target
  producer : CheckedStep
  predecessor : Target?
  completion : SortCompletion?
  key_order : @evidence.KeyedRelation?
  dependencies : Array[Target]
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
    Input(_) => None
    Step(i) => p.logical_orders.get(i).bind(v => v)
  }
}

///|
pub fn order_origin(order : LogicalOrder) -> Target {
  order.origin
}

///|
pub fn order_producer(order : LogicalOrder) -> CheckedStep {
  order.producer
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
) -> Array[LogicalOrder?] raise Stop {
  let out : Array[LogicalOrder?] = []
  for i in 0..<steps.length() {
    let step = steps[i]
    spend(b, step.source, 1)
    let completion = match step.operation {
      Unary(op) if @relation.operation(op) == @relation.Sort &&
        @relation.sort_term_count(op) > 0 =>
        complete_sort(
          b,
          op,
          step.input.bind(t => key_at(t, input_keys, step_keys)),
        )
      _ => None
    }
    let previous = step.input.bind(t => {
      match t {
        Input(_) => None
        Step(j) => out[j]
      }
    })
    let key_order = match step.operation {
      Unary(op) if @relation.operation(op) == @relation.Take && previous is None =>
        select_order_key(
          b,
          op,
          step.input.bind(t => key_at(t, input_keys, step_keys)),
        )
      _ => None
    }
    let preserve = match step.operation {
      Unary(op) => @relation.preserves_input_order(op)
      Calendar(op) => @calendar.input(op) is Some(_)
      Event(op) =>
        match @event.options(op) {
          ToEvents | Watermark(_, _) => true
          _ => false
        }
      Projection(op) => @projection.operation(op) == @projection.Events
      _ => false
    }
    let establishes = match step.operation {
      TimeSeries(_) | Nearest(..) | Ranking(_) | TextRank(..) => true
      GraphMatch(_) | Reach(_) | Traverse(..) | Shortest(..) => true
      Graph(op) => @graph.operation(op) == @graph.Components
      Unary(op) | WindowGroup(op) =>
        match @relation.operation(op) {
          Group | Pivot | DedupeRows => true
          _ => false
        }
      Event(op) => @event.options(op) is Session(_)
      Sequence(_) => true
      Calendar(op) => @calendar.input(op) is None
      _ => false
    }
    let dependencies = match step.operation {
      Append(right~, ..) | CrossJoin(right~, ..) => {
        let right_order = match right {
          Input(_) => None
          Step(j) => out[j]
        }
        match (step.input, previous, right_order) {
          (Some(left), Some(_), Some(_)) => [left, right]
          _ => []
        }
      }
      Unary(op) if @relation.operation(op) == @relation.Unnest ||
        @relation.operation(op) == @relation.Unpivot =>
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
          producer: step,
          predecessor: None,
          completion,
          key_order,
          dependencies,
        })
      } else if preserve {
        previous.map(v => { ..v, predecessor: step.input, })
      } else {
        None
      },
    )
  }
  out
}
