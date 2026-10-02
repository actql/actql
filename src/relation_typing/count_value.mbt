///|
/// An author guard retains the declaration owner and deferred bound validation.
/// It is not a resolved capacity limit or permission to execute.
struct CheckedCountValue {
  source : @decode.Cursor
  value : CountValue
  parameters : @parameter.Declarations?
  pending : Array[PendingValidation]
  usage : (Int, Int)
}

///|
pub fn check_count_value(
  source : @decode.Cursor,
  minimum : Int64,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedCountValue, Issue] {
  try {
    if minimum < 0L ||
      minimum > 9007199254740991L ||
      limits.max_work < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      work: limits.max_work,
      text: limits.max_text_bytes,
      nodes: limits.max_nodes,
      tokens: limits.max_tokens,
      limits,
    }
    let types : Map[String, @contract.Contract] = Map([])
    if parameters is Some(owner) {
      let count = @parameter.declaration_count(owner)
      spend(b, source, count~)
      for i in 0..<count {
        let p = @parameter.declaration_at(owner, i).unwrap()
        charge(b, source, p.name)
        preflight(b, source, p.parameter_type.contract)
        types[p.name] = p.parameter_type.contract
      }
    }
    let pending = []
    let value = row_count(b, source, minimum, types, pending)
    Ok({
      source,
      value,
      parameters,
      pending,
      usage: (limits.max_work - b.work, limits.max_text_bytes - b.text),
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn count_value(value : CheckedCountValue) -> CountValue {
  value.value
}

///|
pub fn count_value_source(value : CheckedCountValue) -> @decode.Cursor {
  value.source
}

///|
pub fn count_value_parameters(
  value : CheckedCountValue,
) -> @parameter.Declarations? {
  value.parameters
}

///|
pub fn count_value_usage(value : CheckedCountValue) -> (Int, Int) {
  value.usage
}

///|
pub fn count_value_pending_count(value : CheckedCountValue) -> Int {
  value.pending.length()
}

///|
pub fn count_value_pending_at(
  value : CheckedCountValue,
  index : Int,
) -> PendingValidation? {
  value.pending.get(index)
}
