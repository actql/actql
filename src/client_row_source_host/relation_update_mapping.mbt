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
    declaration,
    writes_json,
    resource,
    sources,
    FileUpdate,
  )
}

///|
/// Admit the file Mock CREATE profile against its original storage schema.
/// The separately assigned Text key is never a mapped field. Every other
/// storage field must be supplied, including explicitly nullable fields.
pub fn prepare_row_file_create_mapping(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources : Array[RowMappingSource],
) -> Result[RowMapping, RowMappingIssue] {
  prepare_row_guarded_mapping(
    declaration,
    writes_json,
    resource,
    sources,
    FileCreate,
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
  prepare_row_guarded_mapping(
    declaration,
    writes_json,
    resource,
    [],
    FileDelete,
  )
}

///|
priv enum FileMappingKind {
  FileCreate
  FileUpdate
  FileDelete
} derive(Eq)

///|
fn prepare_row_guarded_mapping(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources : Array[RowMappingSource],
  expected : FileMappingKind,
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
        "resource", "primary_identity", "create", "update", "delete",
      ])
      is Ok(fields) &&
      @decode.lookup(fields, "resource").map(@decode.text) is Some(Ok(name)) &&
      @decode.lookup(fields, "primary_identity").map(@decode.text)
      is Some(Ok(identity)) else {
      return Err(InvalidSpecification)
    }
    let (kind, operation) = match
      (
        @decode.lookup(fields, "create"),
        @decode.lookup(fields, "update"),
        @decode.lookup(fields, "delete"),
      ) {
      (Some(create), None, None) => (FileCreate, create)
      (None, Some(update), None) => (FileUpdate, update)
      (None, None, Some(delete)) => (FileDelete, delete)
      _ => return Err(InvalidSpecification)
    }
    let keys = if kind is FileDelete {
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
    let names = if kind is FileDelete {
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
    if kind is FileCreate {
      // The selected file profile assigns a 64-character lowercase SHA-256
      // key. An enum or narrower Text contract cannot accept the key space.
      guard approval == "required" &&
        contract.shape is @contract.Object(fields) &&
        @contract.field_count(fields) == writable_fields.length() + 1 &&
        @schema.lookup_reference(schema, identity) is Some(primary) &&
        !primary.contract.nullable &&
        primary.contract.shape is @contract.Text(bounds) &&
        bounds.enumeration is None &&
        bounds.min_length.unwrap_or(0L) <= 64L &&
        bounds.max_codepoints.unwrap_or(64L) >= 64L &&
        bounds.max_utf8_bytes.unwrap_or(64L) >= 64L else {
        return Err(InvalidSpecification)
      }
    }
    for field in writable_fields {
      if @schema.lookup_reference(schema, field) is None {
        return Err(FieldNotWritable(field))
      }
    }
    if name == resource && kind == expected {
      selected = Some(
        (
          identity,
          {
            kind: if kind is FileCreate {
              RelationCreate
            } else {
              RelationUpdate
            },
            writable_fields,
            required_fields: if kind is FileCreate {
              writable_fields
            } else {
              []
            },
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
  if expected is FileDelete {
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
