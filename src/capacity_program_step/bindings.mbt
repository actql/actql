///|
/// A lookup owned by one checked pipeline and one complete bound collection.
struct CountBindings {
  pipeline : @pipeline.CheckedPipeline
  values : @parameter.BoundValues
  entries : Map[String, @parameter.BoundParameter]
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
  for i in 0..<work {
    let entry = @parameter.bound_value_at(values, i).unwrap()
    // Parameter names have already been admitted as ASCII identifiers.
    let size = entry.name.length()
    if size > max_text_bytes - text {
      return Err(BindingTextLimit)
    }
    text = text + size
    entries[entry.name] = entry
  }
  Ok({ pipeline, values, entries, work, text, })
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
