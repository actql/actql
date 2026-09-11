///|
pub(all) enum ParameterIssue {
  InvalidLimits
  WorkLimit(Int)
  Collection(Int, @parameter_slots.Issue)
  MissingBindings(Int)
  Binding(Int, @references.BindingIssue)
}

///|
pub struct ParameterVisit {
  collected : @parameter_slots.Collected
  bound : @references.BoundIndex?
}

///|
struct BoundParameters {
  context : PipelineContext
  visits : Array[ParameterVisit]
  work : Int
  text : Int
}

///|
/// Bind every local operation reference using the exact values already retained
/// by the context's guard closure. Limits include the earlier context work/text.
/// Source paths are local pipeline coordinates, not staged Program identities.
pub fn check_parameter_bindings(
  context : PipelineContext,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[BoundParameters, ParameterIssue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if context.work > max_work || context.text > max_text_bytes {
    return Err(WorkLimit(0))
  }
  let mut work = context.work
  let mut text = context.text
  let visits : Array[ParameterVisit] = []
  let closure = @results.checked_producer_orders(context.orders)
  for visit in 0..<@pipeline.contextual_closure_count(closure) {
    if work == max_work {
      return Err(WorkLimit(visit))
    }
    work += 1
    let pipeline = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(closure, visit).unwrap(),
    )
    let collected = match
      @parameter_slots.collect(@pipeline.source(pipeline), pipeline, {
        max_work: max_work - work,
        max_slots: max_work - work,
        max_references: max_work - work,
        max_pointer_units: max_work - work,
        max_direct_text_bytes: max_text_bytes - text,
      }) {
      Ok(v) => v
      Err(e) => return Err(Collection(visit, e))
    }
    work += @parameter_slots.work(collected)
    text += @parameter_slots.direct_text_bytes(collected)
    let index = @parameter_slots.index(collected)
    let values = @pipeline.bound_guard_bindings(
      @pipeline.bound_guard_closure_at(context.guards, visit).unwrap(),
    )
    let bound = match values {
      Some(values) => {
        let bound = match
          @references.bind_values(index, values, max_work=max_work - work) {
          Ok(v) => v
          Err(e) => return Err(Binding(visit, e))
        }
        work += @references.binding_work(bound)
        Some(bound)
      }
      None => {
        if @references.reference_count(index) != 0 {
          return Err(MissingBindings(visit))
        }
        None
      }
    }
    visits.push({ collected, bound, })
  }
  Ok({ context, visits, work, text, })
}

///|
pub fn parameter_context(v : BoundParameters) -> PipelineContext {
  v.context
}

///|
pub fn parameter_visit_count(v : BoundParameters) -> Int {
  v.visits.length()
}

///|
pub fn parameter_visit_at(v : BoundParameters, index : Int) -> ParameterVisit? {
  v.visits.get(index)
}

///|
pub fn parameter_usage(v : BoundParameters) -> (Int, Int) {
  (v.work, v.text)
}
