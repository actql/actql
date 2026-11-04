///|
/// The installed UPDATE continuation accepts closed write facts, not a second
/// field schema. Every resource is checked against the retained declaration.
/// Current permission, approval and physical dispatch remain Host duties.
pub fn prepare_row_update_mapping(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources : Array[RowMappingSource],
) -> Result[RowMapping, RowMappingIssue] {
  let limits : RowDeclarationLimits = {
    ..declaration_limits,
    max_fields: 1024,
  }
  let (_, root, _, _) = match
    mapping_read_original(
      writes_json,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.closed_object(root, ["writes"]) is Ok(object) &&
    @decode.lookup(object, "writes") is Some(writes) &&
    @decode.elements(writes) is Ok(writes) &&
    !writes.is_empty() &&
    writes.length() <= limits.max_views else {
    return Err(InvalidSpecification)
  }
  let seen : Array[String] = []
  let mut selected : (String, RowRelationWriteSpec)? = None
  for write in writes {
    guard @decode.closed_object(write, [
        "resource", "primary_identity", "update",
      ])
      is Ok(fields) &&
      @decode.lookup(fields, "resource").map(@decode.text) is Some(Ok(name)) &&
      @decode.lookup(fields, "primary_identity").map(@decode.text)
      is Some(Ok(identity)) &&
      @decode.lookup(fields, "update") is Some(update) &&
      @decode.closed_object(update, ["fields", "permission", "approval"])
      is Ok(update) &&
      @decode.lookup(update, "fields").map(@decode.elements) is Some(Ok(names)) &&
      @decode.lookup(update, "permission").map(@decode.text)
      is Some(Ok(permission)) &&
      @decode.lookup(update, "approval").map(@decode.text) is Some(Ok(approval)) else {
      return Err(InvalidSpecification)
    }
    if seen.contains(name) ||
      name.is_empty() ||
      identity.is_empty() ||
      permission.is_empty() ||
      (approval != "none" && approval != "required") ||
      names.is_empty() ||
      names.length() > limits.max_fields {
      return Err(InvalidSpecification)
    }
    seen.push(name)
    let writable_fields : Array[String] = []
    for field in names {
      guard @decode.text(field) is Ok(field) else {
        return Err(InvalidSpecification)
      }
      if writable_fields.contains(field) || field == identity {
        return Err(InvalidSpecification)
      }
      writable_fields.push(field)
    }
    // Validate even an unselected sibling spec under its own original schema.
    // The selected constructor below remains the only Mapping semantic owner.
    let (_, contract) = match
      mapping_original_relation(declaration, name, identity, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @schema.from_object(contract) is Ok(schema) else {
      return Err(InvalidSpecification)
    }
    for field in writable_fields {
      if @schema.lookup_reference(schema, field) is None {
        return Err(FieldNotWritable(field))
      }
    }
    if name == resource {
      selected = Some(
        (
          identity,
          {
            kind: RelationUpdate,
            writable_fields,
            required_fields: [],
            permission,
            approval,
          },
        ),
      )
    }
  }
  guard selected is Some((identity, spec)) else {
    return Err(NotWritable(resource))
  }
  prepare_relation_row_write_mapping(
    declaration, resource, identity, spec, sources, limits,
  )
}
