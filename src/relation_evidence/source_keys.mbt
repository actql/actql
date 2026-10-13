///|
/// Project only the original environment's opaque SourceView declaration.
/// The normal key-admission obligations remain pending until complete capture.
pub fn source_view_keys(
  view : @model_environment.SourceViewCarrier,
  limits : TransferLimits,
) -> Result[KeySetTransfer?, Issue] {
  guard @model_environment.source_view_relation_keys(view) is Some(declaration) else {
    return Ok(None)
  }
  let reference = @model_environment.source_relation_key_reference(declaration)
  let source = @model_environment.reference_source(reference)
  let carrier = @model_environment.carrier_schema_value(
    @model_environment.source_relation_key_schema(declaration),
  )
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let budget = { work: limits.max_work, text: limits.max_name_bytes, }
    let count = @model_environment.source_relation_key_count(declaration)
    spend(budget, source, count)
    let witnesses = []
    for index in 0..<count {
      let tuple = @model_environment.source_relation_key_at(declaration, index).unwrap()
      let key = match
        declare_primary_key(tuple, carrier, {
          max_fields: budget.work,
          max_name_bytes: budget.text,
        }) {
        Ok(key) => key
        Err(issue) => raise Stop(issue)
      }
      let usage = key_usage(key)
      spend(budget, tuple, usage.fields)
      budget.text -= usage.name_bytes
      witnesses.push(key)
    }
    let keys = match
      collect_keys(source, carrier, witnesses, {
        max_keys: count,
        max_work: budget.work,
        max_name_bytes: budget.text,
      }) {
      Ok(keys) => keys
      Err(issue) => raise Stop(issue)
    }
    let (work, text) = key_set_usage(keys)
    budget.work -= work
    budget.text -= text
    Ok(
      Some({
        keys,
        work: limits.max_work - budget.work,
        name_bytes: limits.max_name_bytes - budget.text,
      }),
    )
  } catch {
    Stop(issue) => Err(issue)
  }
}
