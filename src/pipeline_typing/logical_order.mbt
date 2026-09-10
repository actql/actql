///|
/// Conditional on successful execution of the retained producer and pipeline.
/// This is not a standalone publication or runtime validation certificate.
struct LogicalOrder {
  origin : Target
  producer : CheckedStep
  predecessor : Target?
  completion : SortCompletion?
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
    let preserve = match step.operation {
      Unary(op) => @relation.preserves_input_order(op)
      Calendar(op) => @calendar.input(op) is Some(_)
      _ => false
    }
    let establishes = match step.operation {
      TimeSeries(_) => true
      Calendar(op) => @calendar.input(op) is None
      _ => false
    }
    out.push(
      if establishes || completion is Some(_) {
        Some({ origin: Step(i), producer: step, predecessor: None, completion, })
      } else if preserve {
        previous.map(v => { ..v, predecessor: step.input, })
      } else {
        None
      },
    )
  }
  out
}
