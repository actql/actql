///|
pub struct ProducerOrderIssue {
  pipeline : CheckedPipeline
  issue : Issue
}

///|
struct ContextualClosure {
  entries : Array[ContextualOrders]
  work : Int
  text : Int
  steps : Int
}

///|
/// Checks every producer occurrence, including unused inputs and branches.
/// Repeated owners are charged per occurrence, not silently deduplicated.
pub fn resolve_contextual_closure(
  root : CheckedPipeline,
  max_steps~ : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[ContextualClosure, ProducerOrderIssue] {
  let mut current = root
  try {
    if max_steps < 0 || max_work < 0 || max_text_bytes < 0 {
      fail(root.source, InvalidLimits)
    }
    let mut work = max_work
    let mut text = max_text_bytes
    let mut steps = 0
    let pending = [root]
    let entries : Array[ContextualOrders] = []
    while pending.pop() is Some(pipeline) {
      current = pipeline
      let n = pipeline.produced_inputs.length()
      if work == 0 || n > work - 1 {
        fail(pipeline.source, BudgetExceeded)
      }
      work -= n + 1
      if pipeline.steps.length() > max_steps - steps {
        fail(pipeline.source, BudgetExceeded)
      }
      let checked = match
        resolve_contextual_orders(
          pipeline,
          max_steps=max_steps - steps,
          max_work=work,
          max_text_bytes=text,
        ) {
        Ok(v) => v
        Err(e) => raise Stop(e)
      }
      let (w, t) = contextual_orders_usage(checked)
      work -= w
      text -= t
      steps += pipeline.steps.length()
      entries.push(checked)
      // Reverse push visits producer inputs in their declared order.
      for i = n - 1; i >= 0; i = i - 1 {
        if pipeline.produced_inputs[i] is Some(input) {
          pending.push(input.pipeline)
        }
      }
    }
    Ok({ entries, work: max_work - work, text: max_text_bytes - text, steps, })
  } catch {
    Stop(issue) => Err({ pipeline: current, issue, })
  }
}

///|
pub fn contextual_closure_root(v : ContextualClosure) -> ContextualOrders {
  v.entries[0]
}

///|
pub fn contextual_closure_count(v : ContextualClosure) -> Int {
  v.entries.length()
}

///|
pub fn contextual_closure_at(
  v : ContextualClosure,
  index : Int,
) -> ContextualOrders? {
  v.entries.get(index)
}

///|
pub fn contextual_closure_usage(v : ContextualClosure) -> (Int, Int) {
  (v.work, v.text)
}

///|
pub fn contextual_closure_steps(v : ContextualClosure) -> Int {
  v.steps
}
