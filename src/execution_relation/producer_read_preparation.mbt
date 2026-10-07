///|
priv enum ProducerReadPreparationPhase {
  Field
  ProjectionEntry
  ProjectionName
  ReferenceBytes
  Column
  ColumnBytes
  ColumnName
}

///|
/// Metadata admission under the existing exact binding and entry/name limits.
/// No row is read, copied or exposed before all receiving columns resolve.
struct ProducerReadPreparation {
  bound : BoundProducerInput
  schema : @schema.Schema
  columns : Array[Int]
  max_entries : Int
  max_name_bytes : Int
  projection_count : Int
  mut entries : Int
  mut bytes : Int
  mut field : Int
  mut projection : Int
  mut column : Int
  mut offset : Int
  mut name : @schema.FieldName
  mut actual : String
  mut phase : ProducerReadPreparationPhase
  mut terminal : Bool
}

///|
pub fn start_prepare_producer_read(
  receiver : @lower.BoundPrepared,
  bound : BoundProducerInput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ProducerReadPreparation, ProducerReadIssue] {
  if !completed_output_available(bound.output) {
    return Err(ProducerUnavailable)
  }
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(receiver, bound.receiver) {
    return Err(ForeignReceiver)
  }
  let target = match bound.consumer_step {
    Some(_) => bound.output.target
    None => Input(bound.input_index)
  }
  guard @lower.preparation_schema_at(@lower.bound_preparation(receiver), target)
    is Some(schema) else {
    return Err(InvalidProjection)
  }
  let count = @schema.field_count(schema)
  if count > max_entries {
    return Err(Limit)
  }
  let projection_count = match bound.projection {
    None => 0
    Some(view) => @lower.projection_field_count(view)
  }
  if projection_count > max_entries - count {
    return Err(Limit)
  }
  Ok({
    bound,
    schema,
    columns: [],
    max_entries,
    max_name_bytes,
    projection_count,
    entries: max_entries - count - projection_count,
    bytes: max_name_bytes,
    field: 0,
    projection: 0,
    column: 0,
    offset: 0,
    name: @schema.Unqualified(""),
    actual: "",
    phase: Field,
    terminal: false,
  })
}

///|
pub fn cancel_prepare_producer_read(cursor : ProducerReadPreparation) -> Unit {
  if !cursor.terminal {
    cursor.columns.clear()
  }
  cursor.terminal = true
  cursor.actual = ""
  cursor.name = @schema.Unqualified("")
}

///|
fn producer_read_preparation_fail(
  cursor : ProducerReadPreparation,
  issue : ProducerReadIssue,
) -> Result[ProducerRead?, ProducerReadIssue] {
  cancel_prepare_producer_read(cursor)
  Err(issue)
}

///|
fn producer_reference_parts(name : @schema.FieldName) -> (String, String) {
  match name {
    @schema.Unqualified(text) => ("", text)
    @schema.Qualified(@schema.Left, text) => ("left.", text)
    @schema.Qualified(@schema.Right, text) => ("right.", text)
  }
}

///|
fn producer_reference_unit(prefix : String, text : String, index : Int) -> Int {
  (if index < prefix.length() {
    prefix[index]
  } else {
    text[index - prefix.length()]
  }).to_int()
}

///|
/// One scalar-safe fragment of a borrowed reference spelling. The byte budget
/// retains exactly the old visits, including unsuccessful candidate columns.
fn measure_producer_reference(
  cursor : ProducerReadPreparation,
  name : @schema.FieldName,
) -> Bool {
  let (prefix, text) = producer_reference_parts(name)
  let count = prefix.length().to_int64() + text.length().to_int64()
  let mut index = cursor.offset
  let end = index.to_int64() + 64L
  while index.to_int64() < count && index.to_int64() < end {
    let unit = producer_reference_unit(prefix, text, index)
    let mut units = 1
    let width = if unit < 0x80 {
      1
    } else if unit < 0x800 {
      2
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if index.to_int64() + 1L >= count {
        return false
      }
      let next = producer_reference_unit(prefix, text, index + 1)
      if next < 0xdc00 || next > 0xdfff {
        return false
      }
      units = 2
      4
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return false
    } else {
      3
    }
    if width > cursor.bytes {
      return false
    }
    cursor.bytes -= width
    index += units
  }
  cursor.offset = if index.to_int64() < count { index } else { 0 }
  true
}

///|
fn producer_reference_role_matches(
  left : @schema.FieldName,
  right : @schema.FieldName,
) -> Bool {
  match (left, right) {
    (@schema.Unqualified(_), @schema.Unqualified(_)) => true
    (@schema.Qualified(a, _), @schema.Qualified(b, _)) => a == b
    _ => false
  }
}

///|
/// One metadata transition or at most 64 UTF-16 units plus a surrogate partner.
/// Completion rechecks current availability; partial columns are never a read.
pub fn advance_prepare_producer_read(
  cursor : ProducerReadPreparation,
) -> Result[ProducerRead?, ProducerReadIssue] {
  if cursor.terminal {
    return Err(InvalidLimits)
  }
  if !completed_output_available(cursor.bound.output) {
    return producer_read_preparation_fail(cursor, ProducerUnavailable)
  }
  match cursor.phase {
    Field => {
      if cursor.field == @schema.field_count(cursor.schema) {
        cursor.terminal = true
        return Ok(
          Some({
            bound: cursor.bound,
            schema: cursor.schema,
            columns: cursor.columns,
            max_entries: cursor.max_entries,
            max_name_bytes: cursor.max_name_bytes,
          }),
        )
      }
      cursor.name = @schema.field_at(cursor.schema, cursor.field).unwrap().name
      cursor.projection = 0
      cursor.column = 0
      cursor.offset = 0
      cursor.phase = if cursor.bound.projection is Some(_) {
        ProjectionEntry
      } else {
        ReferenceBytes
      }
    }
    ProjectionEntry => {
      if cursor.projection == cursor.projection_count {
        return producer_read_preparation_fail(cursor, InvalidProjection)
      }
      if cursor.entries == 0 {
        return producer_read_preparation_fail(cursor, Limit)
      }
      cursor.entries -= 1
      guard @lower.projection_field_at(
          cursor.bound.projection.unwrap(),
          cursor.projection,
        )
        is Some(selected) else {
        return producer_read_preparation_fail(cursor, InvalidProjection)
      }
      if producer_reference_role_matches(selected.output, cursor.name) {
        cursor.phase = ProjectionName
      } else {
        cursor.projection += 1
      }
    }
    ProjectionName => {
      guard @lower.projection_field_at(
          cursor.bound.projection.unwrap(),
          cursor.projection,
        )
        is Some(selected) else {
        return producer_read_preparation_fail(cursor, InvalidProjection)
      }
      let (order, next, _) = @schema.compare_reference_fragment(
        selected.output,
        cursor.name,
        cursor.offset,
        64,
      )
      cursor.offset = next
      match order {
        None => ()
        Some(0) => {
          cursor.name = selected.input
          cursor.phase = ReferenceBytes
        }
        Some(_) => {
          cursor.projection += 1
          cursor.phase = ProjectionEntry
        }
      }
    }
    ReferenceBytes => {
      if !measure_producer_reference(cursor, cursor.name) {
        return producer_read_preparation_fail(cursor, Limit)
      }
      if cursor.offset == 0 {
        cursor.phase = Column
      }
    }
    Column => {
      if cursor.column == completed_column_count(cursor.bound.output) {
        return producer_read_preparation_fail(cursor, InvalidProjection)
      }
      if cursor.entries == 0 {
        return producer_read_preparation_fail(cursor, Limit)
      }
      cursor.entries -= 1
      guard completed_column_name(cursor.bound.output, cursor.column)
        is Some(actual) else {
        return producer_read_preparation_fail(cursor, InvalidProjection)
      }
      cursor.actual = actual
      cursor.phase = ColumnBytes
    }
    ColumnBytes => {
      if !measure_producer_reference(cursor, @schema.Unqualified(cursor.actual)) {
        return producer_read_preparation_fail(cursor, Limit)
      }
      if cursor.offset == 0 {
        cursor.phase = ColumnName
      }
    }
    ColumnName => {
      let (order, next, _) = @schema.compare_reference_fragment(
        @schema.Unqualified(cursor.actual),
        cursor.name,
        cursor.offset,
        64,
      )
      cursor.offset = next
      match order {
        None => ()
        Some(0) => {
          cursor.columns.push(cursor.column)
          cursor.field += 1
          cursor.phase = Field
          cursor.actual = ""
        }
        Some(_) => {
          cursor.column += 1
          cursor.phase = Column
        }
      }
    }
  }
  Ok(None)
}

///|
/// A statically bounded metadata lane, never an estimate from measured work.
/// At most eight fields/projection entries and 64-unit reference spellings
/// retain the existing single handoff charge. Larger shapes must resume.
pub fn producer_read_preparation_is_small(
  cursor : ProducerReadPreparation,
) -> Bool {
  if cursor.terminal ||
    @schema.field_count(cursor.schema) > 8 ||
    completed_column_count(cursor.bound.output) > 8 ||
    cursor.projection_count > 8 {
    return false
  }
  fn short(name : @schema.FieldName) -> Bool {
    let (prefix, text) = producer_reference_parts(name)
    prefix.length().to_int64() + text.length().to_int64() <= 64L
  }
  for index in 0..<@schema.field_count(cursor.schema) {
    if !short(@schema.field_at(cursor.schema, index).unwrap().name) {
      return false
    }
  }
  for index in 0..<completed_column_count(cursor.bound.output) {
    guard completed_column_name(cursor.bound.output, index) is Some(name) else {
      return false
    }
    if name.length() > 64 {
      return false
    }
  }
  if cursor.bound.projection is Some(view) {
    for index in 0..<cursor.projection_count {
      guard @lower.projection_field_at(view, index) is Some(field) else {
        return false
      }
      if !short(field.input) || !short(field.output) {
        return false
      }
    }
  }
  true
}
