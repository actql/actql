///|
/// One outcome per validated input tuple preserves the exact selected key.
/// This conditional producer proof is not evidence of observed uniqueness,
/// completed calls, capture, publication or model-egress authority.
pub fn infer_result_keys(
  operation : CheckedInfer,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = operation.source
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 2)
    let n = operation.keys.length()
    spend(b, source, n)
    let fields : Array[KeyField] = []
    for binding in operation.keys {
      charge(b, source, binding.field)
      fields.push(plain_key_field(binding.field, Some(binding.contract)))
    }
    spend(b, source, n)
    let aliases = fields.map(field => [field])
    let records = @carrier.typed_rows(operation.output)
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    let key : KeyedRelation = {
      origin: InferResult,
      producer: Some(InferProducer(operation)),
      source,
      records,
      declared_records: records,
      declared_fields: fields,
      fields,
      aliases,
      usage: { fields: n, name_bytes, },
    }
    Ok({
      keys: { records, witnesses: [key], work, name_bytes, },
      work,
      name_bytes,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn key_infer_producer(key : KeyedRelation) -> CheckedInfer? {
  match key.producer {
    Some(InferProducer(operation)) => Some(operation)
    _ => None
  }
}

///|
/// Retains the input assertion and its pending physical validation obligations.
pub fn key_infer_dependency(key : KeyedRelation) -> KeyedRelation? {
  key_infer_producer(key).map(operation => operation.key_witness)
}
