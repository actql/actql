///|
// One construction owns one admitted value collection. Value interpretation
// is shared across pipelines; each attachment still keeps its exact owner.
priv struct CapacityCountBindings {
  values : @parameter.BoundValues
  mut parameters : @step_bounds.CountParameters?
  pipelines : Map[
    Int,
    Array[(@pipeline.CheckedPipeline, @step_bounds.CountBindings)],
  ]
}

///|
fn capacity_count_bindings(
  values : @parameter.BoundValues,
) -> CapacityCountBindings {
  { values, parameters: None, pipelines: Map([]), }
}

///|
// The returned usage is this call's increment. A cache hit charges lookup,
// not the value scan previously performed by another pipeline attachment.
fn capacity_count_binding(
  session : CapacityCountBindings,
  pipeline : @pipeline.CheckedPipeline,
  max_work : Int,
  max_text_bytes : Int,
) -> Result[(@step_bounds.CountBindings?, Int, Int), @step_bounds.Issue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(@step_bounds.InvalidBindingLimits)
  }
  guard @pipeline.parameters(pipeline) is Some(declarations) else {
    return Ok((None, 0, 0))
  }
  if !physical_equal(
      declarations,
      @parameter.bound_declarations(session.values),
    ) {
    return Err(@step_bounds.BindingOwnerMismatch)
  }
  if max_work == 0 {
    return Err(@step_bounds.BindingWorkLimit)
  }
  let mut work = 1
  let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
  if session.pipelines.get(key) is Some(bucket) {
    for (owner, bindings) in bucket {
      if work == max_work {
        return Err(@step_bounds.BindingWorkLimit)
      }
      work += 1
      if physical_equal(owner, pipeline) {
        return Ok((Some(bindings), work, 0))
      }
    }
  }
  // Reserve the new retained attachment before building its value lookup.
  if work == max_work {
    return Err(@step_bounds.BindingWorkLimit)
  }
  work += 1
  let (parameters, text) = match session.parameters {
    Some(value) => (value, 0)
    None => {
      let value = match
        @step_bounds.prepare_count_parameters(
          session.values,
          max_work=max_work - work,
          max_text_bytes~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let used = @step_bounds.count_parameters_usage(value)
      work += used.0
      (value, used.1)
    }
  }
  let bindings = match
    @step_bounds.bind_prepared_parameters(pipeline, parameters) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  session.parameters = Some(parameters)
  match session.pipelines.get(key) {
    Some(bucket) => bucket.push((pipeline, bindings))
    None => session.pipelines[key] = [(pipeline, bindings)]
  }
  Ok((Some(bindings), work, text))
}
