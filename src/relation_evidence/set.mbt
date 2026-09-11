///|
/// Both policies select left occurrences without changing their values. Wider
/// output field contracts do not invalidate the original left key witness.
pub fn transfer_set_keys(
  previous : KeySet,
  operation : @set.CheckedSet,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @set.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.complete_schema(previous.records) is Some(left) &&
      physical_equal(left, @set.input_schema(operation, Left)) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    spend(b, source, previous.witnesses.length())
    let records = @carrier.typed_rows(@set.output_schema(operation))
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
