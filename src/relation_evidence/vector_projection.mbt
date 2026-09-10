///|
/// Retains the intrinsic identity tuple across the explicit Vectors bridge.
/// Structural roles are not proof of actual member uniqueness or admission.
pub fn vector_projection_keys(
  operation : @projection.CheckedProjection,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @projection.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if @projection.operation(operation) != @projection.Vectors {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let records = @carrier.relation_rows(@projection.output(operation)).unwrap()
    let witnesses : Array[KeyedRelation] = []
    match @projection.input(operation) {
      @carrier.VectorValue(vector) => {
        let n = @carrier.vector_identity_count(vector)
        spend(b, source, n)
        let fields : Array[KeyField] = []
        for i in 0..<n {
          let field = @carrier.vector_identity_at(vector, i).unwrap()
          charge(b, source, field.name)
          fields.push({ name: field.name, contract: field.contract, })
        }
        witnesses.push({
          origin: VectorProjectionResult,
          producer: Some(VectorProjectionProducer(operation)),
          records,
          declared_records: records,
          declared_fields: fields,
          source,
          fields,
          aliases: fields.map(field => [field]),
          usage: { fields: n, name_bytes: limits.max_name_bytes - b.text, },
        })
      }
      _ => () // An opaque Carrier supplies no identity fields or proof.
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}
