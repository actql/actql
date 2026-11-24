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
    let update = @decode.lookup(fields, "update")
    let delete = @decode.lookup(fields, "delete")
    if seen.contains(name) ||
      name.is_empty() ||
      identity.is_empty() ||
      (update is None && delete is None) {
      return Err(InvalidSpecification)
    }
    seen.push(name)
    // Both operations select the same original Relation schema and key.
    let (_, contract) = match
      mapping_original_relation(declaration, name, identity, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @schema.from_object(contract) is Ok(schema) else {
      return Err(InvalidSpecification)
    }
    for (is_delete, candidate) in [(false, update), (true, delete)] {
      guard candidate is Some(operation) else { continue }
      let keys = if is_delete {
        ["permission", "approval"]
      } else {
        ["fields", "permission", "approval"]
      }
      guard @decode.closed_object(operation, keys) is Ok(operation) &&
        @decode.lookup(operation, "permission").map(@decode.text)
        is Some(Ok(permission)) &&
        @decode.lookup(operation, "approval").map(@decode.text)
        is Some(Ok(approval)) &&
        !permission.is_empty() &&
        (approval == "none" || approval == "required") else {
        return Err(InvalidSpecification)
      }
      let writable_fields : Array[String] = []
      if !is_delete {
        guard @decode.lookup(operation, "fields").map(@decode.elements)
          is Some(Ok(names)) &&
          !names.is_empty() &&
          names.length() <= limits.max_fields else {
          return Err(InvalidSpecification)
        }
        for field in names {
          guard @decode.text(field) is Ok(field) &&
            !writable_fields.contains(field) &&
            field != identity else {
            return Err(InvalidSpecification)
          }
          if @schema.lookup_reference(schema, field) is None {
            return Err(FieldNotWritable(field))
          }
          writable_fields.push(field)
        }
      }
      // Validate every declared operation before issuing the selected Mapping.
      if name == resource && is_delete == deleting {
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
