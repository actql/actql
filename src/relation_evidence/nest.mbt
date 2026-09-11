///|
/// Nest retains every parent row and field. The child contributes no parent
/// uniqueness proof. The originating pipeline retains the nest's obligations.
pub fn transfer_nest_keys(
  previous : KeySet,
  operation : @nest.CheckedNest,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @nest.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.complete_schema(previous.records) is Some(parent) &&
      physical_equal(parent, @nest.input_schema(operation, Left)) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    spend(b, source, previous.witnesses.length())
    let records = @carrier.typed_rows(@nest.output_schema(operation))
    let witnesses = previous.witnesses.map(key => { ..key, records, })
    let work = limits.max_work - b.work
    Ok({
      keys: { records, witnesses, work, name_bytes: 0, },
      work,
      name_bytes: 0,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
