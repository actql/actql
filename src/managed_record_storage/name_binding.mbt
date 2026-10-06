///|
/// Virtual qualification avoids assembling a second copy of a long name.
priv struct RecordName {
  prefix : String
  text : String
}

///|
fn record_name(name : @schema.FieldName) -> RecordName {
  match name {
    @schema.Unqualified(text) => { prefix: "", text, }
    @schema.Qualified(@schema.Left, text) => { prefix: "left.", text, }
    @schema.Qualified(@schema.Right, text) => { prefix: "right.", text, }
  }
}

///|
fn record_name_length(name : RecordName) -> Int {
  name.prefix.length() + name.text.length()
}

///|
fn record_name_unit(name : RecordName, index : Int) -> Int {
  if index < name.prefix.length() {
    name.prefix[index].to_int()
  } else {
    name.text[index - name.prefix.length()].to_int()
  }
}

///|
priv enum RecordNamePhase {
  HashName
  BucketName
  SchemaName
  FinishedName
}

///|
priv struct RecordNameBinding {
  target : RecordName
  mut phase : RecordNamePhase
  mut fingerprint : UInt
  mut offset : Int
  mut candidate : Int
  mut lo : Int
  mut hi : Int
}

///|
fn start_record_name(target : RecordName) -> RecordNameBinding {
  {
    target,
    phase: HashName,
    fingerprint: 5381U,
    offset: 0,
    candidate: -1,
    lo: 0,
    hi: 0,
  }
}

///|
/// A fingerprint only selects a bucket; complete UTF-16 comparison proves
/// equality. No identifier normalization or value identity is inferred here.
fn advance_record_name_hash(binding : RecordNameBinding) -> Bool {
  let end = binding.offset +
    (record_name_length(binding.target) - binding.offset).min(64)
  while binding.offset < end {
    binding.fingerprint = binding.fingerprint * 33U +
      record_name_unit(binding.target, binding.offset).reinterpret_as_uint()
    binding.offset += 1
  }
  binding.offset == record_name_length(binding.target)
}

///|
/// Return an order and the number of inspected code-unit pairs. Cursor offsets
/// survive a yield, including a split surrogate pair: raw UTF-16 is the law.
fn compare_record_name(
  binding : RecordNameBinding,
  candidate : RecordName,
  budget : Int,
) -> (Int?, Int) {
  let common = record_name_length(candidate).min(
    record_name_length(binding.target),
  )
  let mut spent = 0
  while binding.offset < common && spent < budget {
    let a = record_name_unit(candidate, binding.offset)
    let b = record_name_unit(binding.target, binding.offset)
    binding.offset += 1
    spent += 1
    if a != b {
      binding.offset = 0
      return (Some(if a < b { -1 } else { 1 }), spent)
    }
  }
  if binding.offset < common {
    return (None, spent)
  }
  binding.offset = 0
  (
    Some(
      if record_name_length(candidate) < record_name_length(binding.target) {
        -1
      } else if record_name_length(candidate) >
        record_name_length(binding.target) {
        1
      } else {
        0
      },
    ),
    spent,
  )
}

///|
/// At most one hash fragment and 64 comparison pairs per poll. Bucket edges
/// are also bounded, even when all names have empty spellings or collide.
fn advance_actual_name(
  cursor : AppendCursor,
  binding : RecordNameBinding,
) -> Int? {
  if binding.phase is FinishedName {
    return Some(binding.candidate)
  }
  if binding.phase is HashName {
    if !advance_record_name_hash(binding) {
      return None
    }
    binding.phase = BucketName
    binding.offset = 0
    binding.candidate = cursor.actual.get(binding.fingerprint).unwrap_or(-1)
  }
  let mut remaining = 64
  guard binding.phase is BucketName else { return None }
  for _ in 0..<8 {
    if binding.candidate < 0 {
      binding.phase = FinishedName
      return Some(-1)
    }
    let (order, spent) = compare_record_name(
      binding,
      record_name(cursor.fields[binding.candidate].0),
      remaining,
    )
    remaining -= spent
    match order {
      None => return None
      Some(0) => {
        binding.phase = FinishedName
        return Some(binding.candidate)
      }
      Some(_) => binding.candidate = cursor.name_links[binding.candidate]
    }
    if remaining == 0 {
      return None
    }
  }
  None
}

///|
/// The existing sorted Knowledge remains the authority. A binary-search cursor
/// changes scheduling only; an equal spelling still requires the typed role.
fn advance_schema_name(
  cursor : AppendCursor,
  binding : RecordNameBinding,
  target : @schema.FieldName,
) -> Int? {
  if !(binding.phase is SchemaName) {
    binding.phase = SchemaName
    binding.lo = 0
    binding.hi = @carrier.field_count(cursor.builder.records)
    binding.candidate = -1
    binding.offset = 0
  }
  let mut remaining = 64
  for _ in 0..<8 {
    if binding.lo >= binding.hi {
      return Some(-1)
    }
    if binding.candidate < 0 {
      binding.candidate = binding.lo + (binding.hi - binding.lo) / 2
    }
    let field = @carrier.field_at(cursor.builder.records, binding.candidate).unwrap()
    let (order, spent) = compare_record_name(
      binding,
      record_name(field.name),
      remaining,
    )
    remaining -= spent
    match order {
      None => return None
      Some(0) => {
        let same_role = match (field.name, target) {
          (@schema.Unqualified(_), @schema.Unqualified(_)) => true
          (@schema.Qualified(a, _), @schema.Qualified(b, _)) => a == b
          _ => false
        }
        return Some(if same_role { binding.candidate } else { -1 })
      }
      Some(order) => {
        if order < 0 {
          binding.lo = binding.candidate + 1
        } else {
          binding.hi = binding.candidate
        }
        binding.candidate = -1
      }
    }
    if remaining == 0 {
      return None
    }
  }
  None
}

///|
fn retain_append_field(
  cursor : AppendCursor,
  name : @schema.FieldName,
  value : @value.CheckedValue,
) -> Unit {
  let key = cursor.binding.unwrap().fingerprint
  cursor.name_links.push(cursor.actual.get(key).unwrap_or(-1))
  cursor.actual[key] = cursor.fields.length()
  cursor.fields.push((name, value))
  cursor.contract_field = None
  cursor.binding = None
  cursor.index += 1
  cursor.phase = Fields
}

///|
fn advance_append_field(cursor : AppendCursor) -> Result[Unit, Issue] {
  guard cursor.contract_field is Some((name, value)) else {
    return Err(InvalidRecord)
  }
  let binding = cursor.binding.unwrap()
  if !(binding.phase is SchemaName) {
    match advance_actual_name(cursor, binding) {
      None => return Ok(())
      Some(index) => if index >= 0 { return Err(InvalidRecord) }
    }
  }
  match advance_schema_name(cursor, binding, name) {
    None => Ok(())
    Some(index) => {
      if index < 0 {
        if @carrier.field_set(cursor.builder.records) == @carrier.Closed {
          return Err(InvalidRecord)
        }
        retain_append_field(cursor, name, value)
      } else {
        guard @carrier.field_at(cursor.builder.records, index).unwrap().contract
          is Some(contract) else {
          return Err(InvalidRecord)
        }
        let check = @contract.start_type_equality(
          contract,
          value.contract,
          cursor.builder.limits.max_contract_work,
        ) catch {
          _ => return Err(InvalidRecord)
        }
        cursor.contract_check = Some(check)
        cursor.contract_field = Some((name, value))
        cursor.phase = FieldContract
        match advance_append_contract(cursor) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok(())
    }
  }
}
