///|
// Original declared write DATA and Common's Mapping, not an installed grant.
// Observe and write permissions retain their separate authored meanings.
pub struct ProjectMockWriteDeclaration {
  mapping : RowMapping
  writable_fields : Array[String]
  aliases : Array[String]
  observe_permission : String
}

///|
fn project_mock_write_names(value : Json?) -> Array[String]? {
  guard value is Some(Array(values)) else { return None }
  let names : Array[String] = []
  for value in values {
    guard value is String(name) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      !names.contains(name) else {
      return None
    }
    names.push(name)
  }
  Some(names)
}

///|
fn project_mock_write_null_fields_valid(
  value : Json?,
  writable : Array[String],
) -> Bool {
  match value {
    None => true
    Some(Array(fields)) => {
      if fields.length() > writable.length() {
        return false
      }
      for index, field in fields {
        guard field is String(name) && writable.contains(name) else {
          return false
        }
        for previous in 0..<index {
          if fields[previous] == field {
            return false
          }
        }
      }
      true
    }
    _ => false
  }
}

///|
fn project_mock_write_null_selected(value : Json?, name : String) -> Bool {
  guard value is Some(Array(fields)) else { return false }
  for field in fields {
    if field is String(selected) && selected == name {
      return true
    }
  }
  false
}

///|
fn project_mock_declaration_text(value : Json, name : String) -> String? {
  guard value is Object(fields) &&
    fields.get(name) is Some(String(text)) &&
    !text.is_empty() &&
    !text.contains("\u{0000}") else {
    return None
  }
  Some(text)
}

///|
/// Prepare the original closed Mock UPDATE or DELETE declaration.
pub fn prepare_project_mock_write_declarations(
  entry : Json,
  declaration : RowDeclaration,
) -> Result[Array[ProjectMockWriteDeclaration], RowMappingIssue] {
  prepare_project_mock_writes(entry, declaration, None, issue => issue)
}

///|
// Keep the authored aliases and Mapping results on the original Project
// reservation. The projected JSON and observer work are charged before either
// adapted input is created; the installed Mapping constructor has its own
// existing quote for each selected resource.
fn project_mock_write_projection_inventory(
  original : RelationRestoreWireGeometry,
  declarations : Int,
  contracts : Int,
  writes : Int,
  collections : Int,
) -> @execution.PreparationRepresentationUnits? {
  let nodes = original.nodes.to_int64()
  let count = writes.to_int64()
  // All dynamic strings are borrowed from the original, and only the field
  // names can occur three times (one write field plus target and source).
  // Price their escaped text and the fixed object/key spellings separately.
  let units = 18L * original.units.to_int64() + 96L * nodes
  let projected_nodes = 8L * nodes
  // The source maps are independently encoded. Bound aggregate work without
  // clamping it to the limit of any one writer.
  guard relation_restore_canonical({
      bytes: 0,
      units: (32L * projected_nodes).to_int(),
      nodes: projected_nodes.to_int(),
      depth: 5,
    })
    is Some(canonical) &&
    relation_construction_writer_units(
      units.to_int(),
      projected_nodes.to_int(),
      5,
    )
    is Some(writer) &&
    // One wrapper writer and one source-map writer per Mapping. The total
    // emitted and visited geometry is charged above; retain fixed controls
    // for the individually opened writers as well.
    relation_restore_emission(0L, 1L, 5, false) is Some(fixed_writer) &&
    relation_restore_scale(fixed_writer, count) is Some(extra_writers) &&
    relation_restore_canonical({ bytes: 0, units: 0, nodes: 1, depth: 5, })
    is Some(fixed_canonical) &&
    relation_restore_scale(fixed_canonical, count) is Some(extra_canonical) &&
    relation_construction_json_forest(projected_nodes) is Some(trees) else {
    return None
  }
  let views = declarations.to_int64()
  let observations = count * (views + 1L) * (contracts.to_int64() + 1L)
  let physical_matches = count * (collections.to_int64() + count)
  @execution.compose_preparation_representation([
    canonical,
    writer,
    extra_writers,
    extra_canonical,
    relation_construction_collection_units(trees),
    {
      // Arrays, source descriptors, alias references, capacity-observer
      // call carriers and original write matching; strings are still loans.
      record_headers: 32L +
      16L * nodes +
      128L * (observations + count) +
      4L * physical_matches,
      reference_slots: 48L +
      34L * nodes +
      192L * (observations + count) +
      8L * physical_matches,
      scalar_words: 48L + 16L * nodes + 128L * (observations + count),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
priv struct ProjectMockWriteFunding[E] {
  original : RelationRestoreWireGeometry
  prepare : (@execution.PreparationRepresentationUnits) -> Result[Unit, E]
  mapping : (
    @execution.ExecutionCapacity,
    () -> Result[RowMapping, RowMappingIssue],
  ) -> Result[RowMapping, E]
}

///|
fn[E] prepare_project_mock_writes(
  entry : Json,
  declaration : RowDeclaration,
  funding : ProjectMockWriteFunding[E]?,
  refusal : (RowMappingIssue) -> E,
) -> Result[Array[ProjectMockWriteDeclaration], E] {
  guard entry is Object(fields) else {
    return Err(refusal(InvalidSpecification))
  }
  let writes = match fields.get("writes") {
    None => return Ok([])
    Some(Array(values)) => values
    _ => return Err(refusal(InvalidSpecification))
  }
  if writes.is_empty() {
    return Ok([])
  }
  guard fields.get("data") is Some(Array(data)) else {
    return Err(refusal(InvalidSpecification))
  }
  if funding is Some(funding) {
    guard project_mock_write_projection_inventory(
        funding.original,
        declaration.views.length(),
        declaration.contracts.length(),
        writes.length(),
        data.length(),
      )
      is Some(projection) else {
      return Err(refusal(InvalidSpecification))
    }
    if (funding.prepare)(projection) is Err(issue) {
      return Err(issue)
    }
  }
  let adapted : Array[Json] = []
  let originals : Array[
    (String, Array[String], Array[String], Array[String], String),
  ] = []
  for write in writes {
    guard write is Object(body) else {
      return Err(refusal(InvalidSpecification))
    }
    let operation = match body.get("operation") {
      None | Some(String("update")) => "update"
      Some(String("delete")) => "delete"
      _ => return Err(refusal(InvalidSpecification))
    }
    guard project_mock_declaration_text(write, "resource") is Some(resource) &&
      project_mock_declaration_text(write, "primary_identity") is Some(identity) &&
      project_mock_declaration_text(write, "permission") is Some(permission) &&
      project_mock_declaration_text(write, "observe_permission")
      is Some(observe) &&
      project_mock_declaration_text(write, "approval") == Some("required") &&
      project_mock_write_names(body.get("aliases")) is Some(aliases) &&
      !aliases.is_empty() else {
      return Err(refusal(InvalidSpecification))
    }
    let (names, selected) = if operation == "delete" {
      // The six common properties and operation exhaust the DELETE object.
      guard body.length() == 7 else {
        return Err(refusal(InvalidSpecification))
      }
      let fields : Array[String] = []
      (fields, fields)
    } else {
      let optional_count = (if body.get("write_null_fields") is Some(_) {
          1
        } else {
          0
        }) +
        (if body.get("update_fields") is Some(_) { 1 } else { 0 }) +
        (if body.get("operation") is Some(_) { 1 } else { 0 })
      guard body.length() == 7 + optional_count &&
        project_mock_write_names(body.get("writable_fields")) is Some(names) &&
        !names.is_empty() &&
        project_mock_write_null_fields_valid(
          body.get("write_null_fields"),
          names,
        ) else {
        return Err(refusal(InvalidSpecification))
      }
      let selected = match body.get("update_fields") {
        None => names
        Some(value) => {
          guard project_mock_write_names(Some(value)) is Some(fields) &&
            !fields.is_empty() &&
            fields.all(name => names.contains(name)) else {
            return Err(refusal(InvalidSpecification))
          }
          fields
        }
      }
      (names, selected)
    }
    guard data
      .iter()
      .find_first(candidate => {
        project_mock_declaration_text(candidate, "resource") == Some(resource)
      })
      is Some(physical) &&
      project_mock_declaration_text(physical, "primary_identity") ==
      Some(identity) else {
      return Err(refusal(InvalidSpecification))
    }
    let specification : Json = if operation == "delete" {
      { "permission": Json::string(permission), "approval": "required" }
    } else {
      {
        "fields": Json::array(names.map(Json::string)),
        "permission": Json::string(permission),
        "approval": "required",
      }
    }
    let facts : Json = match
      adapted
      .iter()
      .find_first(candidate => {
        project_mock_declaration_text(candidate, "resource") == Some(resource)
      }) {
      Some(value) => value
      None => {
        let value : Json = {
          "resource": Json::string(resource),
          "primary_identity": Json::string(identity),
        }
        adapted.push(value)
        value
      }
    }
    guard facts is Object(fields) && fields.get(operation) is None else {
      return Err(refusal(InvalidSpecification))
    }
    fields[operation] = specification
    originals.push((resource, names, selected, aliases, observe))
  }
  let wire = match
    relation_declaration_projection_wire(
      { "writes": Json::array(adapted) },
      declaration_limits.max_bytes,
      declaration_limits.max_nodes,
      declaration_limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(refusal(InvalidSpecification))
  }
  let result : Array[ProjectMockWriteDeclaration] = []
  for index, (resource, names, selected, aliases, observe) in originals {
    let null_fields = match writes[index] {
      Object(body) => body.get("write_null_fields")
      _ => None
    }
    // UPDATE always retains at least one eligible field; an empty field
    // inventory comes only from the explicit closed DELETE declaration.
    let sources : Array[RowMappingSource] = selected.map(name => {
      target: name,
      field: name,
      null_behavior: if project_mock_write_null_selected(null_fields, name) {
        "write_null"
      } else {
        "reject"
      },
    })
    let construct = () => {
      if names.is_empty() {
        prepare_row_delete_mapping_from_writes(declaration, wire, resource)
      } else {
        prepare_row_update_mapping(declaration, wire, resource, sources)
      }
    }
    let admitted = if funding is Some(funding) {
      let source_wire = match
        relation_declaration_projection_wire(
          Json::array(
            sources.map(source => {
              "target": Json::string(source.target),
              "field": Json::string(source.field),
              "null_behavior": Json::string(source.null_behavior),
            }),
          ),
          declaration_limits.max_bytes,
          declaration_limits.max_nodes,
          declaration_limits.max_depth,
        ) {
        Ok(value) => value
        Err(_) => return Err(refusal(InvalidSpecification))
      }
      // Both operations use the original guarded Mapping constructor. DELETE
      // keeps its empty input array and the same sibling declaration checks.
      guard row_update_mapping_construction_capacity(
          declaration, wire, resource, source_wire,
        )
        is Some(capacity) else {
        return Err(refusal(InvalidSpecification))
      }
      (funding.mapping)(capacity, construct)
    } else {
      construct().map_err(refusal)
    }
    let mapping = match admitted {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let writable_fields = if selected.length() == names.length() {
      mapping.write_fields
    } else {
      names
    }
    result.push({
      mapping,
      writable_fields,
      aliases,
      observe_permission: observe,
    })
  }
  Ok(result)
}
