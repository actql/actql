///|
/// A lookup owned by one checked pipeline and one complete bound collection.
struct CountBindings {
  pipeline : @pipeline.CheckedPipeline
  values : @parameter.BoundValues
  entries : Map[String, @parameter.BoundParameter]
  durations : Map[String, Int64]
  work : Int
  text : Int
}

///|
/// Retain an already bound collection; never apply Parameter defaults here.
pub fn bind_parameters(
  pipeline : @pipeline.CheckedPipeline,
  values : @parameter.BoundValues,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[CountBindings, Issue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidBindingLimits)
  }
  guard @pipeline.parameters(pipeline) is Some(declarations) &&
    physical_equal(declarations, @parameter.bound_declarations(values)) else {
    return Err(BindingOwnerMismatch)
  }
  let work = @parameter.bound_value_count(values)
  if work > max_work {
    return Err(BindingWorkLimit)
  }
  let mut text = 0
  let entries : Map[String, @parameter.BoundParameter] = Map([])
  let durations : Map[String, Int64] = Map([])
  for i in 0..<work {
    let entry = @parameter.bound_value_at(values, i).unwrap()
    // Parameter names have already been admitted as ASCII identifiers.
    let size = entry.name.length()
    if size > max_text_bytes - text {
      return Err(BindingTextLimit)
    }
    text = text + size
    if @parameter.bound_parameter_type(entry).rule is @contract.Duration &&
      entry.value.value is Text(value) {
      // Admitted duration tokens are ASCII. Charge before the one-time parse;
      // repeated window references use the cached scalar without rescanning.
      if value.length() > max_text_bytes - text {
        return Err(BindingTextLimit)
      }
      text = text + value.length()
      durations[entry.name] = @scalar.read_duration_ms(value).unwrap()
    }
    entries[entry.name] = entry
  }
  Ok({ pipeline, values, entries, durations, work, text, })
}

///|
fn resolve_milliseconds(
  value : @window.Milliseconds,
  bindings : CountBindings?,
) -> Result[Int64, Issue] {
  match value {
    @window.Literal(n) => Ok(n)
    @window.Parameter(name, duration~, domain~) => {
      guard bindings is Some(bound) else { return Err(UnresolvedCount) }
      let n = if duration {
        bound.durations.get(name)
      } else {
        match bound.entries.get(name) {
          Some(entry) =>
            match entry.value.value {
              Number(n) => @scalar.read_safe_integer(n)
              _ => None
            }
          None => None
        }
      }
      match n {
        Some(n) if domain == @window.SignedMilliseconds || n > 0L => Ok(n)
        _ => Err(InvalidBoundMilliseconds(name))
      }
    }
  }
}

///|
fn window_factor(
  options : @window.Options,
  bindings : CountBindings?,
) -> Result[Int64, Issue] {
  let size = match resolve_milliseconds(@window.size(options), bindings) {
    Ok(n) => n
    Err(e) => return Err(e)
  }
  let step = match @window.step(options) {
    Some(value) =>
      match resolve_milliseconds(value, bindings) {
        Ok(n) => Some(n)
        Err(e) => return Err(e)
      }
    None => None
  }
  match resolve_milliseconds(@window.offset(options), bindings) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  if @window.kind(options) == @window.Fixed {
    return Ok(1L)
  }
  let divisor = step.unwrap() // Checked sliding options always carry a step.
  // Exact ceil(size / step), with no binary64 rounding or size + step overflow.
  Ok(size / divisor + (if size % divisor == 0L { 0L } else { 1L }))
}

///|
fn resolve_count(
  count : @relation.CountValue,
  bindings : CountBindings?,
) -> Result[Int64, Issue] {
  match count {
    @relation.Literal(n) => Ok(n)
    @relation.Parameter(name) => {
      guard bindings is Some(bound) else { return Err(UnresolvedCount) }
      guard bound.entries.get(name) is Some(entry) else {
        return Err(UnresolvedCount)
      }
      guard entry.value.value is Number(n) else {
        return Err(InvalidBoundCount)
      }
      match @scalar.read_safe_integer(n) {
        Some(n) if n > 0L => Ok(n)
        _ => Err(InvalidBoundCount)
      }
    }
  }
}

///|
pub fn parameter_values(bindings : CountBindings) -> @parameter.BoundValues {
  bindings.values
}

///|
pub fn binding_usage(bindings : CountBindings) -> (Int, Int) {
  (bindings.work, bindings.text)
}
