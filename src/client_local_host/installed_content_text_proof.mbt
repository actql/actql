///|
// Finite text from the SAME serializer and transparent metadata copies. This
// never bounds open ContentRef or arbitrary unbounded Text contracts. Inspect
// every original schema and expression, including dormant expression children.
fn installed_content_text_bound(
  content : ClientInstalledEffectContentPreparation,
  sequences : Array[@execution.GeneratedSequence],
  demand : ClientLocalValueNodeDemand,
  ceiling : Int,
) -> Int? {
  if sequences.is_empty() || ceiling < 0 {
    return None
  }
  let owner = @lower.serialization_owner(content.component.barrier)
  let prepared = @lower.bound_preparation(owner)
  let step = content.component.step
  let max_work = client_local_schema_proof_work()
  guard installed_content_schema_node_bound(content, owner, max_work)
    is Some((reference, _, used)) else {
    return None
  }
  let mut remaining = max_work - used
  for sequence in sequences {
    if remaining < 1 ||
      !physical_equal(
        @lower.sequence_owner(@execution.generated_prepared_sequence(sequence)),
        owner,
      ) {
      return None
    }
    remaining -= 1
  }
  let profile = @pipeline.serialization_profile(
    @lower.serialization_checked(content.component.barrier),
  )
  // A UTF-16 code unit contributes at most three UTF-8 bytes. This is a
  // conservative length calculation, not a second encoded metadata copy.
  let name = 3L *
    @publication.content_serialization_name(profile).length().to_int64()
  let media = 3L *
    @publication.content_serialization_media_type(profile).length().to_int64()
  // Pre-issuer schemas/expressions retain the original global row envelope.
  // The proven unary suffix cannot expand the serializer's single output.
  guard @execution.checked_preparation_add_product(
      0L,
      demand.original.max_name_width,
      demand.rows.to_int64(),
    )
    is Some(names) else {
    return None
  }
  let mut text = names
  for index in 0..<@lower.node_count(prepared) {
    if remaining < 1 {
      return None
    }
    remaining -= 1
    guard @lower.node_at(prepared, index) is Some(node) &&
      @lower.node_relation_schema(node) is Some(schema) else {
      return None
    }
    if index > step {
      match @lower.payload(node) {
        @lower.Derive(operation) =>
          for binding in 0..<@relation.binding_count(operation) {
            if remaining < 1 {
              return None
            }
            remaining -= 1
            guard @relation.binding_copy_at(operation, binding) is Some(copy) &&
              copy.output is Some(output) else {
              return None
            }
            if output == "name" || output == "media_type" || output == "content" {
              guard copy.input is Some(@relation.InputField(input)) &&
                @schema.reference_name(input) == output else {
                return None
              }
            }
          }
        @lower.Select(operation) =>
          for field in 0..<@relation.projection_field_count(operation) {
            if remaining < 1 {
              return None
            }
            remaining -= 1
            guard @relation.projection_field_at(operation, field) is Some(copy) else {
              return None
            }
            let output = @schema.reference_name(copy.output)
            if (
                output == "name" ||
                output == "media_type" ||
                output == "content"
              ) &&
              @schema.reference_name(copy.input) != output {
              return None
            }
          }
        _ => () // The existing nominal node proof already fences suffix kinds.
      }
    }
    for field in 0..<@schema.field_count(schema) {
      if remaining < 1 {
        return None
      }
      remaining -= 1
      guard @schema.field_at(schema, field) is Some(field) else { return None }
      let contract = @schema.field_contract(field)
      let field_name = Some(@schema.field_reference_name(field))
      let bytes = match contract.shape {
        @contract.Number | @contract.Boolean => 0L
        @contract.Text(bounds) =>
          match bounds.max_utf8_bytes {
            Some(bytes) => if bytes < 0L { return None } else { bytes }
            None =>
              if index >= step && field_name == Some("name") {
                name
              } else if index >= step && field_name == Some("media_type") {
                media
              } else {
                return None
              }
          }
        @contract.ContentRef(_) =>
          if index >= step &&
            field_name == Some("content") &&
            physical_equal(contract, reference) {
            content.reference_bytes.to_int64()
          } else {
            return None
          }
        _ => return None
      }
      let copies = if index >= step { 1L } else { demand.rows.to_int64() }
      guard @execution.checked_preparation_add_product(text, bytes, copies)
        is Some(next) else {
        return None
      }
      text = next
    }
  }
  let slots = match
    @pipeline.collect_expression_slots(
      @lower.pipeline(prepared),
      max_work=remaining,
      max_slots=client_local_scalar_text_proof_slots(),
    ) {
    Ok(slots) => slots
    Err(_) => return None
  }
  let used = @pipeline.expression_slots_work(slots)
  if used < 0 || used > remaining {
    return None
  }
  remaining -= used
  for index in 0..<@pipeline.expression_slot_count(slots) {
    guard @pipeline.expression_slot_at(slots, index) is Some(slot) else {
      return None
    }
    let mut metadata_copy = false
    if slot.step > step && @typing.node_count(slot.expression) == 1 {
      guard @lower.node_at(prepared, slot.step) is Some(node) else {
        return None
      }
      if @lower.payload(node) is @lower.Derive(operation) {
        for binding in 0..<@relation.binding_count(operation) {
          if remaining < 1 {
            return None
          }
          remaining -= 1
          if @relation.binding_expression_at(operation, binding)
            is Some(expression) &&
            physical_equal(expression, slot.expression) &&
            @relation.binding_copy_at(operation, binding) is Some(copy) &&
            copy.input is Some(@relation.InputField(input)) {
            let name = @schema.reference_name(input)
            metadata_copy = name == "content" ||
              name == "name" ||
              name == "media_type"
          }
        }
      }
    }
    for index in 0..<@typing.node_count(slot.expression) {
      if remaining < 1 {
        return None
      }
      remaining -= 1
      guard @typing.node_at(slot.expression, index) is Some(node) else {
        return None
      }
      match node.contract.shape {
        @contract.Number | @contract.Boolean => ()
        @contract.Text(bounds) =>
          match bounds.max_utf8_bytes {
            Some(bytes) => {
              if bytes < 0L {
                return None
              }
              let copies = if slot.step > step {
                1L
              } else {
                demand.rows.to_int64()
              }
              guard @execution.checked_preparation_add_product(
                  text, bytes, copies,
                )
                is Some(next) else {
                return None
              }
              text = next
            }
            None => if !metadata_copy { return None }
          }
        @contract.ContentRef(_) => if !metadata_copy { return None }
        _ => return None
      }
    }
  }
  guard client_local_scalar_product(text, 1, 0) is Some(total) else {
    return None
  }
  Some(Int::min(ceiling, total))
}
