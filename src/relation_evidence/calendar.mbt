///|
/// Bucket adds a fresh field without changing rows or existing field values.
/// Only the checked operation's bound input can supply retained witnesses.
pub fn transfer_calendar_keys(
  previous : KeySet,
  operation : @calendar.CheckedCalendar,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @calendar.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @calendar.input(operation) is Some(@carrier.Relation(input)) &&
      same_records(previous.records, input) else {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    spend(b, source, previous.witnesses.length())
    let records = @carrier.relation_rows(@calendar.output(operation)).unwrap()
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

///|
/// Bucket transfers existing keys; series establishes its start-field key.
/// The retained Calendar producer carries its profile and execution obligations.
pub fn advance_calendar_keys(
  previous : KeySet?,
  operation : @calendar.CheckedCalendar,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    let source = @calendar.source(operation)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if @calendar.input(operation) is Some(_) {
      let keys = previous.unwrap_or({
        records: @carrier.relation_rows(@calendar.input(operation).unwrap()).unwrap(),
        witnesses: [],
        work: 0,
        name_bytes: 0,
      })
      return transfer_calendar_keys(keys, operation, limits)
    }
    if previous is Some(_) {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 2)
    let records = @carrier.relation_rows(@calendar.output(operation)).unwrap()
    let name = @row.Unqualified("start")
    charge(b, source, name)
    let contract = match @carrier.lookup(records, name) {
      Present(field) => field.contract
      _ => fail(source, InputContractMismatch)
    }
    let fields : Array[KeyField] = [{ name, contract, }]
    let key : KeyedRelation = {
      origin: CalendarSeriesResult,
      producer: Some(CalendarProducer(operation)),
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
