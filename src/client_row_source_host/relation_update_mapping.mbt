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
  FileUpsert
} derive(Eq)

///|
/// Select an insert-capable Mapping for the same original complete File row.
/// Every non-key field must be supplied because an approved key can be absent.
pub fn prepare_row_file_upsert_mapping(
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
    FileUpsert,
  )
}

///|
fn file_tuple_identity_body(fields : Array[String]) -> Json {
  object([
    ("kind", "tuple".to_json()),
    ("fields", Json::array(fields.map(field => field.to_json()))),
  ])
}

///|
fn relation_file_tuple_key_valid(
  schema : @schema.Schema,
  fields : Array[String],
) -> Bool {
  fields.all(name => {
    guard @schema.lookup_reference(schema, name) is Some(field) else {
      return false
    }
    !field.contract.nullable &&
    (
      field.contract.shape is @contract.Text(_) ||
      field.contract.shape is @contract.Signed64
    )
  })
}

///|
fn file_write_key(
  cursor : @decode.Cursor,
  max_fields : Int,
) -> (String, Array[String]?)? {
  if @decode.text(cursor) is Ok(identity) {
    return Some((identity, None))
  }
  guard @decode.closed_object(cursor, ["kind", "fields"]) is Ok(tuple) &&
    @decode.lookup(tuple, "kind").map(@decode.text) is Some(Ok("tuple")) &&
    @decode.lookup(tuple, "fields") is Some(fields) &&
    @decode.array_length(fields) is Some(width) &&
    width >= 2 &&
    width <= max_fields else {
    return None
  }
  let names : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for index in 0..<width {
    guard @decode.text(@decode.element_at(fields, index).unwrap()) is Ok(name) &&
      !name.is_empty() &&
      !seen.contains(name) else {
      return None
    }
    seen[name] = true
    names.push(name)
  }
  Some((names[0], Some(names)))
}

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
  let mut selected : (String, Array[String]?, RowRelationWriteSpec)? = None
  for write in writes {
    guard @decode.closed_object(write, [
        "resource", "primary_identity", "create", "update", "delete", "upsert",
      ])
      is Ok(fields) &&
      @decode.lookup(fields, "resource").map(@decode.text) is Some(Ok(name)) &&
      @decode.lookup(fields, "primary_identity") is Some(key) &&
      file_write_key(key, limits.max_fields) is Some((identity, ordered)) else {
      return Err(InvalidSpecification)
    }
    let create = @decode.lookup(fields, "create")
    let update = @decode.lookup(fields, "update")
    let delete = @decode.lookup(fields, "delete")
    let upsert = @decode.lookup(fields, "upsert")
    if seen.contains(name) ||
      name.is_empty() ||
      identity.is_empty() ||
      (create is None && update is None && delete is None && upsert is None) {
      return Err(InvalidSpecification)
    }
    seen.push(name)
    // All operations select the same original Relation schema and key.
    let (_, contract) = match
      mapping_original_relation(
        declaration,
        name,
        identity,
        limits,
        ordered_key=ordered,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @schema.from_object(contract) is Ok(schema) else {
      return Err(InvalidSpecification)
    }
    if ordered is Some(fields) && !relation_file_tuple_key_valid(schema, fields) {
      return Err(InvalidSpecification)
    }
    for
      (kind, candidate) in [
        (FileCreate, create),
        (FileUpdate, update),
        (FileDelete, delete),
        (FileUpsert, upsert),
      ] {
      guard candidate is Some(operation) else { continue }
      if (kind is FileCreate && ordered is Some(_)) ||
        (kind is FileUpsert && ordered is None) {
        return Err(InvalidSpecification)
      }
      let is_delete = kind is FileDelete
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
            field != identity &&
            !ordered.map(fields => fields.contains(field)).unwrap_or(false) else {
            return Err(InvalidSpecification)
          }
          if @schema.lookup_reference(schema, field) is None {
            return Err(FieldNotWritable(field))
          }
          writable_fields.push(field)
        }
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
      if kind is FileUpsert {
        guard ordered is Some(fields) &&
          approval == "required" &&
          contract.shape is @contract.Object(all) &&
          @contract.field_count(all) ==
          writable_fields.length() + fields.length() else {
          return Err(InvalidSpecification)
        }
      }
      // Validate every declared operation before issuing the selected Mapping.
      if name == resource && kind == expected {
        selected = Some(
          (
            identity,
            ordered,
            {
              kind: if kind is FileCreate {
                RelationCreate
              } else {
                RelationUpdate
              },
              writable_fields,
              required_fields: if kind is (FileCreate | FileUpsert) {
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
  }
  guard selected is Some((identity, ordered, spec)) else {
    return Err(NotWritable(resource))
  }
  if ordered is Some(fields) {
    return prepare_relation_row_write_mapping_original(
      declaration,
      resource,
      identity,
      spec,
      sources,
      limits,
      tuple=Some((expected, fields)),
    )
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
