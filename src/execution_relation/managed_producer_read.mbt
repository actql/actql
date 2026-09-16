///|
/// A checked receiving view of one managed completed occurrence. This is
/// binding evidence only, not a pin, current use authorization or budget credit.
/// Its column ordinals address the admitted logical schema, not backend slots.
struct ManagedProducerRead[T] {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  input_index : Int
  output : ManagedCompletedOutput[T]
  schema : @schema.Schema
  columns : Array[Int]
}

///|
pub(all) enum ManagedProducerReadIssue {
  Binding(ProducerBindingIssue)
  View(ProducerReadIssue)
}

///|
/// The Host supplies the exact expected parameter-bound producer. Equal schema,
/// values, profile pin or physical digest cannot stand in for that invocation.
/// Only the projection already checked on the receiving input is admitted.
pub fn[T] prepare_managed_producer_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : ManagedCompletedOutput[T],
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ManagedProducerRead[T], ManagedProducerReadIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(View(InvalidLimits))
  }
  if !managed_completed_output_available(output) {
    return Err(Binding(ProducerUnavailable))
  }
  match
    validate_producer_binding_owner(
      receiver,
      input_index,
      expected_producer,
      completion_preparation_owner(output.preparation),
      output.target,
    ) {
    Err(issue) => return Err(Binding(issue))
    Ok(_) => ()
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.preparation_schema_at(prepared, Input(input_index))
    is Some(schema) else {
    return Err(View(InvalidProjection))
  }
  let count = @schema.field_count(schema)
  if count > max_entries {
    return Err(View(Limit))
  }
  let mut remaining = max_entries - count
  let mut bytes = max_name_bytes
  let view = @lower.preparation_input_projection(prepared, input_index)
  let projection = match view {
    None => []
    Some(view) => {
      let size = @lower.projection_field_count(view)
      if size > remaining {
        return Err(View(Limit))
      }
      remaining -= size
      @lower.projection_fields(view)
    }
  }
  let source = output.material.receipt.schema
  let columns = []
  for index in 0..<count {
    let field = @schema.field_at(schema, index).unwrap()
    let mut name = field.name
    if view is Some(_) {
      let mut found = false
      for selected in projection {
        if remaining == 0 {
          return Err(View(Limit))
        }
        remaining -= 1
        if selected.output == field.name {
          name = selected.input
          found = true
          break
        }
      }
      if !found {
        return Err(View(InvalidProjection))
      }
    }
    let reference = @schema.reference_name(name)
    match @scalar.admit_utf8_length(reference, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(View(Limit))
    }
    let mut found = None
    for column in 0..<@schema.field_count(source) {
      if remaining == 0 {
        return Err(View(Limit))
      }
      remaining -= 1
      let actual = @schema.reference_name(
        @schema.field_at(source, column).unwrap().name,
      )
      match @scalar.admit_utf8_length(actual, bytes) {
        Ok(size) => bytes -= size
        Err(_) => return Err(View(Limit))
      }
      if actual == reference {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) else { return Err(View(InvalidProjection)) }
    columns.push(column)
  }
  if !managed_completed_output_available(output) {
    return Err(Binding(ProducerUnavailable))
  }
  Ok({ identity: Ref(()), receiver, input_index, output, schema, columns, })
}

///|
pub fn[T] managed_producer_read_available(
  input : ManagedProducerRead[T],
) -> Bool {
  managed_completed_output_available(input.output)
}

///|
pub fn[T] managed_producer_read_receiver(
  input : ManagedProducerRead[T],
) -> @lower.BoundPrepared {
  input.receiver
}

///|
pub fn[T] managed_producer_read_input_index(
  input : ManagedProducerRead[T],
) -> Int {
  input.input_index
}

///|
pub fn[T] managed_producer_read_schema(
  input : ManagedProducerRead[T],
) -> @schema.Schema {
  input.schema
}

///|
pub fn[T] managed_producer_read_row_count(
  input : ManagedProducerRead[T],
) -> Int {
  input.output.material.receipt.rows
}

///|
pub fn[T] managed_producer_read_column(
  input : ManagedProducerRead[T],
  column : Int,
) -> Int? {
  input.columns.get(column)
}

///|
/// Exact receiving use-site identity, not content or output occurrence equality.
pub fn[T] managed_producer_read_same_binding(
  left : ManagedProducerRead[T],
  right : ManagedProducerRead[T],
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
/// Installed Host lookup only. Dispatch still requires Store pin, use authority
/// and resource admission. No old CID-bearing material is manufactured here.
pub fn[T] managed_producer_read_material(
  input : ManagedProducerRead[T],
) -> ManagedRetainedOutput[T]? {
  if managed_producer_read_available(input) {
    Some(input.output.material)
  } else {
    None
  }
}

///|
/// Installed representation registry binding. Does not grant a Store pin or
/// current use authority; projection remains the checked receiving view.
pub fn[T] managed_producer_read_matches_material(
  input : ManagedProducerRead[T],
  material : ManagedRetainedOutput[T],
) -> Bool {
  physical_equal(input.output.material, material) &&
  managed_producer_read_available(input)
}

///|
/// Common graph scheduling compares the exact completed occurrence without
/// learning or serializing the representation payload.
pub fn[T] managed_producer_read_matches_reference(
  input : ManagedProducerRead[T],
  reference : ManagedCompletionReference,
) -> Bool {
  managed_completed_reference_matches(reference, input.output) &&
  managed_producer_read_available(input)
}
