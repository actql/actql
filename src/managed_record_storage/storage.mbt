///|
pub(all) struct Limits {
  max_input_records : Int
  max_records : Int
  max_fields_per_record : Int
  max_value_bytes : Int
  max_total_value_bytes : Int
  max_retained_value_bytes : Int
  max_value_nodes : Int
  max_value_depth : Int
  max_contract_work : Int
  max_work : Int
  max_workspace_slots : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  WrongCarrier
  InvalidRecord
  InvalidIdentity
  InputRecordLimit
  RecordLimit
  FieldLimit
  ValueLimit
  RetainedValueLimit
  WorkLimit
  WorkspaceLimit
  DuplicateIdentity
  Closed
} derive(Eq, Debug)

///|
priv struct Record {
  fields : Array[(@schema.FieldName, @value.CheckedValue)]
}

///|
struct Builder {
  carrier : @carrier.Carrier
  records : @carrier.Knowledge
  identities : Array[String]
  limits : Limits
  values : Array[Record]
  keys : Map[String, Bool]
  mut input_records : Int
  mut value_bytes : Int
  mut retained_value_bytes : Int
  mut work : Int
  mut workspace_slots : Int
  mut open : Bool
  mut owns_private : Bool
}

///|
struct Storage {
  carrier : @carrier.Carrier
  identities : Array[String]
  values : Array[Record]
  input_records : Int
  value_bytes : Int
  retained_value_bytes : Int
  work : Int
  workspace_slots : Int
}

///|
fn valid_limits(limits : Limits) -> Bool {
  limits.max_input_records >= 0 &&
  limits.max_records >= 0 &&
  limits.max_fields_per_record >= 0 &&
  limits.max_value_bytes >= 0 &&
  limits.max_total_value_bytes >= 0 &&
  limits.max_retained_value_bytes >= 0 &&
  limits.max_value_nodes >= 0 &&
  limits.max_value_depth >= 0 &&
  limits.max_contract_work >= 0 &&
  limits.max_work >= 0 &&
  limits.max_workspace_slots >= 0
}

///|
fn identity_names(value : @carrier.Carrier) -> Array[String]? {
  match value {
    @carrier.EventValue(events) =>
      Some([@schema.reference_name(@carrier.event_identity(events).name)])
    @carrier.VectorValue(vectors) => {
      let names = []
      for identity in @carrier.vector_identities(vectors) {
        names.push(@schema.reference_name(identity.name))
      }
      Some(names)
    }
    _ => None
  }
}

///|
fn carrier_records(value : @carrier.Carrier) -> @carrier.Knowledge? {
  match value {
    @carrier.EventValue(events) => Some(@carrier.event_records(events))
    @carrier.VectorValue(vectors) => Some(@carrier.vector_records(vectors))
    _ => None
  }
}

///|
pub fn prepare(
  carrier : @carrier.Carrier,
  limits : Limits,
) -> Result[Builder, Issue] {
  prepare_with_additional_identities(carrier, [], limits)
}

///|
/// Prepare storage whose physical record key includes operation-owned fields
/// in addition to the Carrier identity. This does not change the Carrier's
/// semantic event identity.
pub fn prepare_with_additional_identities(
  carrier : @carrier.Carrier,
  additional : Array[@schema.FieldName],
  limits : Limits,
) -> Result[Builder, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  guard carrier_records(carrier) is Some(records) &&
    identity_names(carrier) is Some(base_identities) else {
    return Err(WrongCarrier)
  }
  if base_identities.is_empty() {
    return Err(InvalidIdentity)
  }
  let identities = base_identities.copy()
  for field in additional {
    let name = @schema.reference_name(field)
    if identities.contains(name) {
      return Err(InvalidIdentity)
    }
    guard @carrier.lookup(records, field) is @carrier.Present(field_entry) &&
      field_entry.contract is Some(contract) &&
      !contract.nullable &&
      @contract.key_comparable(contract, contract) else {
      return Err(InvalidIdentity)
    }
    identities.push(name)
  }
  Ok({
    carrier,
    records,
    identities,
    limits,
    values: [],
    keys: Map([]),
    input_records: 0,
    value_bytes: 0,
    retained_value_bytes: 0,
    work: 0,
    workspace_slots: 0,
    open: true,
    owns_private: true,
  })
}

///|
fn fail(builder : Builder, issue : Issue) -> Result[Unit, Issue] {
  builder.open = false
  Err(issue)
}

///|
fn contract_equal(
  builder : Builder,
  left : @contract.Contract,
  right : @contract.Contract,
) -> Bool {
  @contract.type_equal(left, right, builder.limits.max_contract_work) catch {
    _ => false
  }
}

///|
fn checked_fields(
  builder : Builder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
) -> Map[String, @value.CheckedValue]? {
  if fields.length() > builder.limits.max_fields_per_record {
    return None
  }
  let actual : Map[String, @value.CheckedValue] = Map([])
  for (name, value) in fields {
    let spelling = @schema.reference_name(name)
    if actual.contains(spelling) {
      return None
    }
    match @carrier.lookup(builder.records, name) {
      @carrier.Present(expected) => {
        guard expected.contract is Some(contract) &&
          contract_equal(builder, contract, value.contract) else {
          return None
        }
      }
      @carrier.Absent => return None
      @carrier.Unknown => ()
    }
    actual[spelling] = value
  }
  for expected in @carrier.fields(builder.records) {
    if !actual.contains(@schema.reference_name(expected.name)) {
      return None
    }
  }
  if @carrier.field_set(builder.records) == @carrier.Closed &&
    fields.length() != @carrier.field_count(builder.records) {
    return None
  }
  Some(actual)
}

///|
fn encode_values(
  builder : Builder,
  values : Array[@value.CheckedValue],
  pending_bytes : Int,
  pending_work : Int,
) -> Result[(String, Int, Int), Issue] {
  if pending_work > builder.limits.max_work - builder.work {
    return Err(WorkLimit)
  }
  let remaining_work = builder.limits.max_work - builder.work - pending_work
  let node_limit = Int::min(builder.limits.max_value_nodes, remaining_work)
  if node_limit < 1 {
    return Err(WorkLimit)
  }
  if pending_bytes > builder.limits.max_total_value_bytes - builder.value_bytes {
    return Err(ValueLimit)
  }
  let remaining = builder.limits.max_total_value_bytes -
    builder.value_bytes -
    pending_bytes
  let byte_limit = Int::min(builder.limits.max_value_bytes, remaining)
  if byte_limit < 0 {
    return Err(ValueLimit)
  }
  try {
    let out = @encode.writer(
      byte_limit,
      node_limit,
      builder.limits.max_value_depth,
    )
    @encode.begin_array(out)
    for value in values {
      @value.emit_wire_value(value.value, out)
    }
    @encode.end_array(out)
    let (text, bytes, nodes, _) = @encode.finish_text_usage(out)
    Ok((text, bytes, nodes))
  } catch {
    _ =>
      if node_limit < builder.limits.max_value_nodes {
        Err(WorkLimit)
      } else {
        Err(ValueLimit)
      }
  }
}

///|
fn encode_record(
  builder : Builder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
  pending_bytes : Int,
  pending_work : Int,
) -> Result[(String, Int, Int), Issue] {
  if pending_work > builder.limits.max_work - builder.work {
    return Err(WorkLimit)
  }
  let remaining_work = builder.limits.max_work - builder.work - pending_work
  let node_limit = Int::min(builder.limits.max_value_nodes, remaining_work)
  if node_limit < 1 {
    return Err(WorkLimit)
  }
  if pending_bytes > builder.limits.max_total_value_bytes - builder.value_bytes {
    return Err(ValueLimit)
  }
  let remaining = builder.limits.max_total_value_bytes -
    builder.value_bytes -
    pending_bytes
  let byte_limit = Int::min(builder.limits.max_value_bytes, remaining)
  if byte_limit < 0 {
    return Err(ValueLimit)
  }
  try {
    let out = @encode.writer(
      byte_limit,
      node_limit,
      builder.limits.max_value_depth,
    )
    @encode.begin_array(out)
    for (name, value) in fields {
      @encode.begin_array(out)
      @encode.string_value(out, @schema.reference_name(name))
      @value.emit_wire_value(value.value, out)
      @encode.end_array(out)
    }
    @encode.end_array(out)
    let (text, bytes, nodes, _) = @encode.finish_text_usage(out)
    Ok((text, bytes, nodes))
  } catch {
    _ =>
      if node_limit < builder.limits.max_value_nodes {
        Err(WorkLimit)
      } else {
        Err(ValueLimit)
      }
  }
}

///|
fn reserve(
  builder : Builder,
  bytes : Int,
  retained_bytes : Int,
  work : Int,
  slots : Int,
) -> Issue? {
  if builder.input_records >= builder.limits.max_input_records {
    return Some(InputRecordLimit)
  }
  if builder.values.length() >= builder.limits.max_records {
    return Some(RecordLimit)
  }
  if bytes > builder.limits.max_total_value_bytes - builder.value_bytes {
    return Some(ValueLimit)
  }
  if retained_bytes >
    builder.limits.max_retained_value_bytes - builder.retained_value_bytes {
    return Some(RetainedValueLimit)
  }
  if work > builder.limits.max_work - builder.work {
    return Some(WorkLimit)
  }
  if slots > builder.limits.max_workspace_slots - builder.workspace_slots {
    return Some(WorkspaceLimit)
  }
  None
}

///|
pub fn append(
  builder : Builder,
  fields : Array[(@schema.FieldName, @value.CheckedValue)],
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  if fields.length() > builder.limits.max_fields_per_record {
    return fail(builder, FieldLimit)
  }
  guard checked_fields(builder, fields) is Some(actual) else {
    return fail(builder, InvalidRecord)
  }
  let identities = []
  for name in builder.identities {
    guard actual.get(name) is Some(value) else {
      return fail(builder, InvalidIdentity)
    }
    identities.push(value)
  }
  let overhead = fields.length() + 1
  let (key, key_bytes, key_work) = match
    encode_values(builder, identities, 0, overhead) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  if builder.keys.contains(key) {
    return fail(builder, DuplicateIdentity)
  }
  let (_, record_bytes, record_work) = match
    encode_record(builder, fields, key_bytes, key_work + overhead) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let bytes = key_bytes + record_bytes
  let work = key_work + record_work + overhead
  let slots = fields.length() + 2
  match reserve(builder, bytes, bytes, work, slots) {
    Some(issue) => return fail(builder, issue)
    None => ()
  }
  builder.values.push({ fields: fields.copy(), })
  builder.keys[key] = true
  builder.input_records += 1
  builder.value_bytes += bytes
  builder.retained_value_bytes += bytes
  builder.work += work
  builder.workspace_slots += slots
  Ok(())
}

///|
pub fn finish(builder : Builder) -> Result[Storage, Issue] {
  if !builder.open || !builder.owns_private {
    return Err(Closed)
  }
  builder.open = false
  builder.owns_private = false
  Ok({
    carrier: builder.carrier,
    identities: builder.identities,
    values: builder.values,
    input_records: builder.input_records,
    value_bytes: builder.value_bytes,
    retained_value_bytes: builder.retained_value_bytes,
    work: builder.work,
    workspace_slots: builder.workspace_slots,
  })
}

///|
pub fn cancel(builder : Builder) -> Bool {
  if !builder.owns_private {
    return false
  }
  builder.open = false
  builder.owns_private = false
  builder.values.clear()
  builder.keys.clear()
  builder.retained_value_bytes = 0
  builder.workspace_slots = 0
  true
}

///|
/// Structural slots already retained by records accepted into this builder.
pub fn builder_workspace_slots(builder : Builder) -> Int {
  builder.workspace_slots
}

///|
pub fn builder_record_count(builder : Builder) -> Int {
  builder.values.length()
}

///|
pub fn builder_retained_value_bytes(builder : Builder) -> Int {
  builder.retained_value_bytes
}

///|
pub fn builder_measured_input_value_bytes(builder : Builder) -> Int {
  builder.value_bytes
}

///|
pub fn builder_construction_work(builder : Builder) -> Int {
  builder.work
}

///|
pub fn carrier(value : Storage) -> @carrier.Carrier {
  value.carrier
}

///|
pub fn record_count(value : Storage) -> Int {
  value.values.length()
}

///|
pub fn input_record_count(value : Storage) -> Int {
  value.input_records
}

///|
pub fn identity_count(value : Storage) -> Int {
  value.identities.length()
}

///|
pub fn identity_name_at(value : Storage, index : Int) -> String? {
  value.identities.get(index)
}

///|
pub fn record_field_count(value : Storage, record : Int) -> Int? {
  value.values.get(record).map(row => row.fields.length())
}

///|
pub fn record_field_at(
  value : Storage,
  record : Int,
  field : Int,
) -> (@schema.FieldName, @value.CheckedValue)? {
  value.values.get(record).bind(row => row.fields.get(field))
}

///|
pub fn measured_input_value_bytes(value : Storage) -> Int {
  value.value_bytes
}

///|
pub fn retained_value_bytes(value : Storage) -> Int {
  value.retained_value_bytes
}

///|
pub fn construction_work(value : Storage) -> Int {
  value.work
}

///|
pub fn retained_workspace_slots(value : Storage) -> Int {
  value.workspace_slots
}

///|
/// Dispose private material whose completed generation was never handed off.
pub fn discard(value : Storage) -> Unit {
  value.values.clear()
}
