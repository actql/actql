///|
// A contextual bound from this SAME installed producer, never a bound on the
// open ContentRef type. Restrict the proof to its source-free original owner
// and a transparent unary suffix; unsupported transformations keep fallback.
fn installed_content_schema_node_bound(
  content : ClientInstalledEffectContentPreparation,
  owner : @lower.BoundPrepared,
  max_work : Int,
) -> (@contract.Contract, Int, Int)? {
  let barrier = content.component.barrier
  let prepared = @lower.bound_preparation(owner)
  let step = @lower.serialization_step(barrier)
  let count = @lower.node_count(prepared)
  if !physical_equal(owner, @lower.serialization_owner(barrier)) ||
    @lower.preparation_input_count(prepared) != 0 ||
    content.reference_nodes < 1 ||
    content.reference_bytes < 1 ||
    count > max_work {
    return None
  }
  guard @lower.preparation_schema_at(prepared, @pipeline.Step(step))
    is Some(schema) &&
    @schema.lookup_reference(schema, "content") is Some(field) else {
    return None
  }
  let contract = @schema.field_contract(field)
  guard contract.shape is @contract.ContentRef(_) else { return None }
  let mut work = count
  for index in (step + 1)..<count {
    guard @lower.node_at(prepared, index) is Some(node) &&
      @lower.node_input_count(node) == 1 &&
      @lower.node_input_target(node, 0) == Some(@pipeline.Step(index - 1)) else {
      return None
    }
    match @lower.payload(node) {
      @lower.Derive(operation) => {
        let bindings = @relation.binding_count(operation)
        if bindings > max_work - work {
          return None
        }
        work += bindings
        for binding in 0..<bindings {
          guard @relation.binding_copy_at(operation, binding) is Some(copy) &&
            copy.output is Some(name) else {
            return None
          }
          if name == "content" || name == "name" || name == "media_type" {
            guard copy.input is Some(@relation.InputField(input)) &&
              @schema.reference_name(input) == name else {
              return None
            }
          }
        }
      }
      @lower.Select(operation) => {
        let fields = @relation.projection_field_count(operation)
        if fields > max_work - work {
          return None
        }
        work += fields
        for index in 0..<fields {
          guard @relation.projection_field_at(operation, index) is Some(field) else {
            return None
          }
          let name = @schema.reference_name(field.output)
          if (name == "content" || name == "name" || name == "media_type") &&
            @schema.reference_name(field.input) != name {
            return None
          }
        }
      }
      @lower.Where(_)
      | @lower.Sort(_)
      | @lower.Limit(_)
      | @lower.AssertRows(_) => ()
      _ => return None
    }
  }
  Some((contract, content.reference_nodes, work))
}
