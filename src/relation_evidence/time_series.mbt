///|
/// A checked positive-step series establishes a conditional unique time field.
pub fn time_series_keys(
  operation : @series.CheckedSeries,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @series.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 2)
    let name = @row.Unqualified("time")
    charge(b, source, name)
    let records = @carrier.relation_rows(@series.output(operation)).unwrap()
    let contract = match @carrier.lookup(records, name) {
      Present(field) => field.contract
      _ => fail(source, InputContractMismatch)
    }
    let fields : Array[KeyField] = [{ name, contract, }]
    let key : KeyedRelation = {
      origin: TimeSeriesResult,
      producer: Some(TimeSeriesProducer(operation)),
      records,
      declared_records: records,
      declared_fields: fields,
      source,
      fields,
      aliases: [fields],
      usage: { fields: 1, name_bytes: limits.max_name_bytes - b.text, },
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    Ok({
      keys: { records, witnesses: [key], work, name_bytes, },
      work,
      name_bytes,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
