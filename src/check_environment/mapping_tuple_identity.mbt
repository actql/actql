///|
fn mapping_tuple_charge(
  work : Ref[Int],
  max_work : Int,
  amount : Int,
) -> Unit raise MappingShapeStop {
  if amount > max_work - work.val {
    raise MappingShapeStop(WorkLimit)
  }
  work.val += amount
}

///|
fn mapping_tuple_fields(
  identity : @decode.Cursor,
  schema : @row.Schema,
  index : Int,
  work : Ref[Int],
  max_work : Int,
) -> Array[String] raise MappingShapeStop {
  guard @decode.closed_object(identity, ["kind", "fields"]) is Ok(object) &&
    mapping_shape_text(object, "kind", index) == "tuple" else {
    raise MappingShapeStop(InvalidMapping(index))
  }
  let list = mapping_shape_required(object, "fields", index)
  guard @decode.array_length(list) is Some(count) && count >= 2 else {
    raise MappingShapeStop(InvalidMapping(index))
  }
  mapping_tuple_charge(work, max_work, count)
  let fields = []
  let seen : Map[String, Bool] = Map([])
  for ordinal in 0..<count {
    guard @decode.text(@decode.element_at(list, ordinal).unwrap()) is Ok(name) &&
      !name.is_empty() else {
      raise MappingShapeStop(InvalidMapping(index))
    }
    mapping_tuple_charge(work, max_work, name.length())
    if seen.contains(name) {
      raise MappingShapeStop(InvalidMapping(index))
    }
    seen[name] = true
    guard @row.lookup_reference(schema, name) is Some(field) &&
      @row.field_presence(field) == @row.Required else {
      raise MappingShapeStop(InvalidTargetSchema(index))
    }
    let contract = @row.field_contract(field)
    if contract.nullable ||
      !(contract.shape is @value_contract.Text(_) ||
      contract.shape is @value_contract.Signed64) {
      raise MappingShapeStop(InvalidTargetSchema(index))
    }
    fields.push(name)
  }
  fields
}

///|
fn mapping_tuple_rule(kind : String, selector : String) -> Bool {
  match (kind, selector) {
    ("update", "match_tuple")
    | ("delete", "match_tuple")
    | ("upsert", "key_tuple") => true
    _ => false
  }
}

///|
fn mapping_tuple_published_key(
  environment : WireEnvironment,
  carriers : CarrierSchemas?,
  connector : ConnectorManifestEntry,
  target : String,
  schema : @row.Schema,
  fields : Array[String],
  index : Int,
  limits : Limits,
  work : Ref[Int],
  max_work : Int,
) -> Unit raise MappingShapeStop {
  guard carriers is Some(original) else {
    raise MappingShapeStop(InvalidMapping(index))
  }
  let shapes = original.modes.shapes
  let policies = shapes.values.policies
  guard physical_equal(
    policies.references.contents.registry.environment,
    environment,
  ) else {
    raise MappingShapeStop(InvalidMapping(index))
  }
  // File relation declarations publish the exact Resource's records view.
  // Its checked output policy binds the complete SourceRef, and its checked
  // Carrier binds both the stored schema and the candidate key occurrence.
  mapping_tuple_charge(work, max_work, target.length())
  mapping_tuple_charge(work, max_work, "#records".length())
  let source_ref = target + "#records"
  let mut selected : SourceRelationKeys? = None
  for view in shapes.views {
    mapping_tuple_charge(work, max_work, 1)
    guard source_view_policy(policies, view) is Some(policy) else { continue }
    let name = policy.policy.source_ref
    mapping_tuple_charge(work, max_work, name.length())
    if name != source_ref {
      continue
    }
    let catalog = policy.reference.catalog
    guard selected is None &&
      catalog.connector == connector.connector_id &&
      catalog.version == connector.connector_version &&
      @decode.open_object(member_body(view)) is Ok(body) &&
      @decode.lookup(body, "view_id").map(@decode.text) == Some(Ok("records")) &&
      source_view_carrier(original, view) is Some(carrier) &&
      carrier.relation_keys is Some(keys) else {
      raise MappingShapeStop(InvalidMapping(index))
    }
    selected = Some(keys)
  }
  guard selected is Some(keys) &&
    @carrier.relation_rows(keys.schema.carrier) is Some(rows) else {
    raise MappingShapeStop(InvalidMapping(index))
  }
  let mut matching = false
  for (_, candidate, _) in keys.facts.tuples {
    mapping_tuple_charge(work, max_work, 1)
    if candidate.length() != fields.length() {
      continue
    }
    let mut equal = true
    for ordinal, field in fields {
      mapping_tuple_charge(work, max_work, field.length())
      mapping_tuple_charge(work, max_work, candidate[ordinal].length())
      if field != candidate[ordinal] {
        equal = false
        break
      }
    }
    if equal {
      matching = true
      break
    }
  }
  if !matching {
    raise MappingShapeStop(InvalidMapping(index))
  }
  for name in fields {
    guard @carrier.lookup(rows, @row.Unqualified(name)) is Present(source) &&
      source.contract is Some(published) else {
      raise MappingShapeStop(InvalidTargetSchema(index))
    }
    let target = @row.field_contract(
      @row.lookup_reference(schema, name).unwrap(),
    )
    mapping_tuple_charge(work, max_work, limits.max_nodes)
    let equal = @value_contract.type_equal(published, target, limits.max_nodes) catch {
      _ => raise MappingShapeStop(WorkLimit)
    }
    if !equal {
      raise MappingShapeStop(InvalidTargetSchema(index))
    }
  }
}
