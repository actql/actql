///|
/// The static ceilings of the Local files and contents views. Physical read
/// and transfer limits stay on the owning Source read.
pub(all) struct LocalFileSourceDeclarationLimits {
  max_files : Int
  max_entries : Int
  max_pages : Int
  max_attempts : Int
  max_listing_bytes : Int
  max_duration_ms : Int
  max_path_bytes : Int
  max_page_bytes : Int
}

///|
fn local_file_source_wire(
  value : Json,
  limits : RowDeclarationLimits,
) -> String raise {
  let canonical = @identity.from_json(
    value,
    limits.max_nodes,
    limits.max_depth,
    limits.max_bytes,
    data_keys=true,
  )
  @identity.stringify_value(
    canonical,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
}

///|
fn local_file_source_identity(wire : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(wire))
}

///|
fn local_file_source_view(
  resource : String,
  schema : Json,
  fields : Json,
  acquisition : Json,
  limits : RowDeclarationLimits,
) -> RowRelationViewSpec raise {
  let request : Json = {
    "type": "object",
    "nullable": false,
    "additional_properties": false,
    "fields": fields,
  }
  let schema_wire = local_file_source_wire(schema, limits)
  {
    resource,
    resource_kind: "file",
    schema_wire,
    schema_cid: local_file_source_identity(schema_wire),
    request_schema_wire: Some(local_file_source_wire(request, limits)),
    facts_wire: Some("{}"),
    acquisition_wire: Some(local_file_source_wire(acquisition, limits)),
  }
}

///|
// Compute the exact schema identity needed by carrier facts without issuing
// a provisional Catalog. The same Relation envelope preimage names this body.
fn local_file_source_carrier_cid(
  connection : String,
  view : RowRelationViewSpec,
  limits : RowDeclarationLimits,
) -> String raise {
  let fields = @json.parse(view.schema_wire)
  let body = object([
    ("fields", fields),
    ("version", "actql-relation-schema/0.1".to_json()),
  ])
  canonical_cid(
    object(
      row_declaration_contract_fields(
        connection + "/" + view.resource + "/records/row",
        "local/0.1",
        "carrier_schema",
        body,
      ),
    ),
    limits,
  )
}

///|
// The closed specification has ten canonical writer calls: two each for
// schema, request, acquisition and facts, and one each for scope and version.
// References and limits in those bodies are fixed-width. Only the borrowed
// connection and Root can add escaped text to the fixed grammar.
fn local_file_source_specification_peak(
  connection : String,
  root : String,
) -> Int64? {
  let fixed_bytes = 4096
  let fixed_nodes = 256
  let depth = 8
  let calls = 10L
  let bytes = fixed_bytes + 6 * (connection.length() + root.length())
  guard relation_construction_json_forest(fixed_nodes.to_int64()) is Some(tree) &&
    relation_public_projection_canonical(
      fixed_nodes,
      fixed_nodes * depth,
      calls,
    )
    is Some(canonical) &&
    relation_construction_writer_units(
      bytes,
      fixed_nodes,
      depth * calls.to_int(),
    )
    is Some(writer) &&
    relation_restore_raw_json({
      bytes: fixed_bytes,
      units: fixed_bytes,
      nodes: fixed_nodes,
      depth,
    })
    is Some(carrier_parse) &&
    relation_restore_emission(
      fixed_bytes.to_int64() + 12L * connection.length().to_int64(),
      fixed_nodes.to_int64(),
      depth,
      true,
    )
    is Some(carrier_emit) &&
    @execution.compose_preparation_representation([
      relation_construction_collection_units(tree),
      canonical,
      writer,
      carrier_parse,
      carrier_emit,
      // The two schema, scope and version digests consume UTF-8 and hash
      // controls. The two carrier hashes are covered by carrier_emit.
      {
        record_headers: 128L,
        reference_slots: 96L,
        scalar_words: 64L,
        owned_utf16_units: 4L * 263L,
        owned_wire_bytes: bytes.to_int64() + 4L * 224L,
      },
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}

///|
// The extra vectors hold the existing checked views and their parallel
// Relation inputs. One CSV view adds 36 representation records to the
// inventory walk: schema and roles, field controls, five envelopes,
// acquisition defaults, source-view seal, and two evidence writers.
// CSV declares neither a custom acquisition nor a resource identity.
fn local_file_csv_declaration_inventory(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  let views = count.to_int64() + 2L
  let terms = 36L * count.to_int64()
  guard @execution.preparation_array_representation(9L, views, true)
    is Some(arguments) &&
    @execution.preparation_array_representation(1L, terms, true)
    is Some(quote_terms) else {
    return None
  }
  @execution.compose_preparation_representation([
    arguments,
    quote_terms,
    {
      record_headers: terms + 3L,
      reference_slots: 3L,
      scalar_words: 5L * terms + 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
// After specification return, hold only its exact arguments beside the
// original Relation constructor. The completed writer peak does not stack.
fn local_file_source_declaration_peak(
  connection : String,
  root : String,
  views : Array[RowRelationViewSpec],
  csv_inventory : @execution.PreparationRepresentationUnits?,
) -> Int64? {
  let mut text = 142L // Scope and version CIDs are both present during issuance.
  for view in views {
    for
      wire in [
        Some(view.schema_wire),
        Some(view.schema_cid),
        view.request_schema_wire,
        view.facts_wire,
        view.acquisition_wire,
      ] {
      if wire is Some(wire) {
        text += wire.length().to_int64()
      }
    }
  }
  let parts : Array[@execution.PreparationRepresentationUnits] = [
    {
      record_headers: 32L,
      reference_slots: 64L,
      scalar_words: 32L,
      owned_utf16_units: text,
      owned_wire_bytes: 0L,
    },
  ]
  if csv_inventory is Some(inventory) {
    parts.push(inventory)
  }
  guard relation_restore_inputs_inventory(
      connection,
      "local",
      "local/0.1",
      views.length(),
      index => {
        let view = views[index]
        (
          view.resource,
          view.resource_kind,
          view.schema_wire,
          view.request_schema_wire,
          view.facts_wire,
          view.acquisition_wire,
          None,
        )
      },
      local_file_root=Some(root),
    )
    is Some(relation) else {
    return None
  }
  parts.push(relation)
  @execution.compose_preparation_representation(parts).bind(
    @execution.preparation_representation_cost,
  )
}

///|
// Return only the typed declaration inputs. Temporary schema/canonical
// bodies, their writers and hashes finish before the Relation issuer.
fn local_file_source_specification(
  connection : String,
  root : String,
  content_version : Bool,
  selected : LocalFileSourceDeclarationLimits,
  limits : RowDeclarationLimits,
) -> (RowRelationViewSpec, RowRelationViewSpec, String, String) raise {
  let string = fn(nullable : Bool) -> Json {
    { "type": "string", "nullable": Json::boolean(nullable) }
  }
  let timestamp = fn(nullable : Bool) -> Json {
    { "type": "timestamp", "nullable": Json::boolean(nullable) }
  }
  let resource : Json = {
    "type": "resource_ref",
    "resource_kind": "file",
    "nullable": false,
  }
  let listing = local_file_source_view(
    "files",
    {
      "resource": resource,
      "version": string(false),
      "name": string(false),
      "path": string(false),
      "size": { "type": "int64", "nullable": false },
      "modified_time": timestamp(false),
      "media_type": string(true),
      "size_bytes": { "type": "number", "nullable": true },
      "modified_at": timestamp(true),
    },
    {
      "paths": {
        "type": "array",
        "nullable": true,
        "max_items": selected.max_files.to_json(),
        "items": string(false),
      },
      "glob": string(true),
    },
    { "kind": "scan", "authority": "read_metadata" },
    limits,
  )
  let content = local_file_source_view(
    "contents",
    {
      "resource": resource,
      "version": string(false),
      "path": string(false),
      "media_type": string(false),
      "content": { "type": "content_ref", "nullable": false },
    },
    { "resource": resource, "version": string(false) },
    {
      "kind": "fetch",
      "authority": "read_content",
      "correlation": {
        "request_fields": ["resource", "version"],
        "response_fields": ["resource", "version"],
        "identity": ["resource", "version"],
        "cardinality": "one",
      },
    },
    limits,
  )
  let listing_carrier = local_file_source_carrier_cid(
    connection, listing, limits,
  )
  let content_carrier = local_file_source_carrier_cid(
    connection, content, limits,
  )
  let scope = local_file_source_wire(
    {
      "connector": "local",
      "connection": Json::string(connection),
      "root": Json::string(root),
    },
    limits,
  )
  let version = local_file_source_wire(
    {
      "connector": "local",
      "version_mode": if content_version {
        "content"
      } else {
        "metadata"
      },
      "representation": "exact_stored_bytes",
      "metadata_fields": ["size", "modified_seconds", "modified_nanos"],
    },
    limits,
  )
  let scope = local_file_source_identity(scope)
  let version = local_file_source_identity(version)
  let version_capability : Json = {
    "contract_cid": Json::string(version),
    "required_nonnull": true,
  }
  let listing = {
    ..listing,
    facts_wire: Some(
      local_file_source_wire(
        {
          "file_listing": {
            "version": "actql-file-list/0.1",
            "kind": "file_listing",
            "selectable": ["paths", "glob"],
            "allow_unfiltered_listing": true,
            "admitted_scope_contract_cid": Json::string(scope),
            "listing_schema_contract_cid": Json::string(listing_carrier),
            "version_capability": version_capability,
            "max_listing_items": selected.max_files.to_json(),
            "max_examined_items": selected.max_entries.to_json(),
            "max_listing_pages": selected.max_pages.to_json(),
            "max_request_attempts": selected.max_attempts.to_json(),
            "max_listing_bytes": selected.max_listing_bytes.to_json(),
            "max_listing_duration_ms": selected.max_duration_ms.to_json(),
            "maximum_path_length": selected.max_path_bytes.to_json(),
          },
        },
        limits,
      ),
    ),
  }
  let content = {
    ..content,
    facts_wire: Some(
      local_file_source_wire(
        {
          "file_content": {
            "version": "actql-file-content/0.1",
            "kind": "file_content",
            "admitted_scope_contract_cid": Json::string(scope),
            "content_schema_contract_cid": Json::string(content_carrier),
            "version_capability": version_capability,
            "representation": "exact_stored_bytes",
          },
          "lookup_capacity": {
            "version": "actql-lookup-capacity/0.1",
            "completeness": "complete_per_requested_key",
            "max_rows_per_key": 1,
            "max_pages_per_request": selected.max_pages.to_json(),
            "max_response_bytes_per_page": selected.max_page_bytes.to_json(),
          },
        },
        limits,
      ),
    ),
  }
  (listing, content, scope, version)
}

///|
/// Holds the exact completed File/CSV specification between the two existing
/// construction reservations. Only this owner can issue its Catalog and STORE.
pub struct PreparedLocalFileSourceDeclaration {
  priv connection : String
  priv root : String
  priv views : Array[RowRelationViewSpec]
  priv scope : String
  priv version : String
  priv csv_inventory : @execution.PreparationRepresentationUnits?
  priv csv_classification : (Int, @environment.DataClassification)?
  priv mut issued : Bool
}

///|
fn valid_local_file_source_declaration_selection(
  connection : String,
  root : String,
  selected : LocalFileSourceDeclarationLimits,
  csv_count : Int,
) -> Bool {
  valid_connector_id(connection) &&
  root.has_prefix("/") &&
  !root.contains("\u{0000}") &&
  @scalar.admit_utf8_length(root, 4096) is Ok(_) &&
  selected.max_files > 0 &&
  selected.max_entries >= selected.max_files &&
  selected.max_entries <= 100000 &&
  selected.max_pages > 0 &&
  selected.max_attempts >= selected.max_pages &&
  selected.max_listing_bytes > 0 &&
  selected.max_duration_ms > 0 &&
  selected.max_path_bytes > 0 &&
  selected.max_path_bytes <= 4096 &&
  selected.max_page_bytes > 0 &&
  csv_count >= 0 &&
  csv_count <= local_file_max_csv_views()
}

///|
/// Quote the existing first phase from the selected connection and Root. This
/// operation has no Catalog or provisional STORE, even at the exact limit.
pub fn local_file_source_specification_construction_capacity(
  connection : String,
  root : String,
  selected : LocalFileSourceDeclarationLimits,
  csv_count : Int,
) -> Result[Int64, RowHostIssue] {
  guard valid_local_file_source_declaration_selection(
      connection, root, selected, csv_count,
    ) &&
    local_file_source_specification_peak(connection, root) is Some(base) else {
    return Err(InvalidSpecification)
  }
  if csv_count == 0 {
    return Ok(base)
  }
  guard local_file_csv_declaration_inventory(csv_count) is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(extra) &&
    @execution.checked_preparation_add_product(base, extra, 1L) is Some(total) else {
    return Err(InvalidSpecification)
  }
  Ok(total)
}

///|
/// Prepare the exact view vector after the original first-phase allowance.
/// There is no reference back to the caller's mutable array after this return.
pub fn prepare_local_file_source_declaration(
  connection : String,
  root : String,
  content_version : Bool,
  selected : LocalFileSourceDeclarationLimits,
  csv_views : Array[RowRelationViewSpec],
  csv_classification? : (Int, @environment.DataClassification)? = None,
) -> Result[PreparedLocalFileSourceDeclaration, RowHostIssue] {
  let csv_count = csv_views.length()
  guard valid_local_file_source_declaration_selection(
    connection, root, selected, csv_count,
  ) else {
    return Err(InvalidSpecification)
  }
  if csv_classification is Some((index, classification)) &&
    (index < 0 || index >= csv_count || classification is @environment.Unknown) {
    return Err(InvalidSpecification)
  }
  let csv_inventory = if csv_count == 0 {
    None
  } else {
    guard local_file_csv_declaration_inventory(csv_count) is Some(inventory) else {
      return Err(InvalidSpecification)
    }
    Some(inventory)
  }
  try {
    let limits = { ..declaration_limits, max_fields: 1024, }
    let (listing, content, scope, version) = local_file_source_specification(
      connection, root, content_version, selected, limits,
    )
    let views = [listing, content]
    for view in csv_views {
      // Only the admitted read-only CSV shape is added. The standard
      // Relation constructor still checks schemas, facts and duplicate names.
      if view.resource_kind != "record" ||
        view.resource == "files" ||
        view.resource == "contents" ||
        view.request_schema_wire is Some(_) ||
        view.acquisition_wire is Some(_) ||
        view.facts_wire is None {
        return Err(InvalidSpecification)
      }
      views.push(view)
    }
    Ok({
      connection,
      root,
      views,
      scope,
      version,
      csv_inventory,
      csv_classification,
      issued: false,
    })
  } catch {
    _ => Err(InvalidSpecification)
  }
}

///|
/// Quote the existing second phase from the held original measured views.
pub fn PreparedLocalFileSourceDeclaration::construction_capacity(
  self : Self,
) -> Result[Int64, RowHostIssue] {
  if self.issued {
    return Err(InvalidState)
  }
  guard local_file_source_declaration_peak(
      self.connection,
      self.root,
      self.views,
      self.csv_inventory,
    )
    is Some(bytes) else {
    return Err(InvalidSpecification)
  }
  Ok(bytes)
}

///|
/// Issue the Catalog and STORE together once the second phase was granted by
/// the caller. The complete catalog includes the two File views and CSV views.
pub fn PreparedLocalFileSourceDeclaration::issue(
  self : Self,
) -> Result[(RowDeclaration, String, String), RowHostIssue] {
  if self.issued {
    return Err(InvalidState)
  }
  self.issued = true
  let limits = { ..declaration_limits, max_fields: 1024, }
  // File and content remain unclassified. The operator's selected CSV
  // classification enters the same Relation Catalog and its View policy.
  let classifications = self.csv_classification.map(selected => {
    let (index, classification) = selected
    let values = Array::make(self.views.length(), @environment.Unknown)
    values[index + 2] = classification
    values
  })
  generate_relation_row_declaration_with_resource_identities(
    self.connection,
    "local",
    "local/0.1",
    self.views,
    limits,
    classifications,
    None,
    Some(self.root),
  ).map(value => (value, self.scope, self.version))
}
