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
  prepare_row_guarded_mapping(
    declaration, writes_json, resource, sources, false,
  )
}

///|
/// Select a DELETE from the original declared write inventory. Common
/// validates every sibling before issuing a Mapping without field values.
pub fn prepare_row_delete_mapping_from_writes(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
) -> Result[RowMapping, RowMappingIssue] {
  prepare_row_guarded_mapping(declaration, writes_json, resource, [], true)
}

///|
fn prepare_row_guarded_mapping(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources : Array[RowMappingSource],
  deleting : Bool,
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
        "resource", "primary_identity", "update", "delete",
      ])
      is Ok(fields) &&
      @decode.lookup(fields, "resource").map(@decode.text) is Some(Ok(name)) &&
      @decode.lookup(fields, "primary_identity").map(@decode.text)
      is Some(Ok(identity)) else {
      return Err(InvalidSpecification)
    }
    let (delete, operation) = match
      (@decode.lookup(fields, "update"), @decode.lookup(fields, "delete")) {
      (Some(update), None) => (false, update)
      (None, Some(delete)) => (true, delete)
      _ => return Err(InvalidSpecification)
    }
    let keys = if delete {
      ["permission", "approval"]
    } else {
      ["fields", "permission", "approval"]
    }
    guard @decode.closed_object(operation, keys) is Ok(operation) &&
      @decode.lookup(operation, "permission").map(@decode.text)
      is Some(Ok(permission)) &&
      @decode.lookup(operation, "approval").map(@decode.text)
      is Some(Ok(approval)) else {
      return Err(InvalidSpecification)
    }
    let names = if delete {
      []
    } else {
      guard @decode.lookup(operation, "fields").map(@decode.elements)
        is Some(Ok(names)) &&
        !names.is_empty() &&
        names.length() <= limits.max_fields else {
        return Err(InvalidSpecification)
      }
      names
    }
    if seen.contains(name) ||
      name.is_empty() ||
      identity.is_empty() ||
      permission.is_empty() ||
      (approval != "none" && approval != "required") {
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
    if name == resource && delete == deleting {
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
  if deleting {
    prepare_row_delete_mapping(
      declaration,
      resource,
      identity,
      spec.permission,
      spec.approval,
      limits,
    )
  } else {
    prepare_relation_row_write_mapping(
      declaration, resource, identity, spec, sources, limits,
    )
  }
}
