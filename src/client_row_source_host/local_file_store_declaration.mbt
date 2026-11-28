///|
priv struct LocalFileStoreCommand {
  input : Json
  input_cid : String
  output : Json
  output_cid : String
  body : Json
  cid : String
  id : String
}

///|
fn local_file_store_fields() -> Json {
  {
    "content": { "nullable": false, "type": "content_ref" },
    "overwrite": { "nullable": false, "type": "boolean" },
    "path": { "nullable": false, "type": "string" },
  }
}

///|
fn local_file_store_contract_reference(id : String, cid : String) -> Json {
  { "cid": cid.to_json(), "id": id.to_json(), "version": "local/0.1" }
}

///|
fn local_file_store_command(
  connection : String,
  limits : RowDeclarationLimits,
) -> LocalFileStoreCommand raise @encode.EncodeFailure {
  let prefix = connection + ".local.files.store."
  let input_id = prefix + "command_input"
  let output_id = prefix + "command_output"
  let input_body : Json = {
    "additional_properties": false,
    "fields": local_file_store_fields(),
    "required_fields": ["content", "path"],
  }
  let output_body : Json = {
    "additional_properties": false,
    "fields": {},
    "nullable": false,
    "type": "object",
  }
  let (input, input_cid) = seal(
    row_declaration_contract_fields(
      input_id, "local/0.1", "command_input", input_body,
    ),
    "cid",
    limits,
  )
  let (output, output_cid) = seal(
    row_declaration_contract_fields(
      output_id, "local/0.1", "command_output", output_body,
    ),
    "cid",
    limits,
  )
  let id = "command:" + prefix + "v1"
  let (body, cid) = seal(
    [
      ("schema", "actql.command_contract/0.1".to_json()),
      ("command_id", id.to_json()),
      ("connector_id", connection.to_json()),
      ("version", "local/0.1".to_json()),
      (
        "target",
        { "cardinality": "single", "resource_kind": "file_collection" },
      ),
      ("input_schema", local_file_store_contract_reference(input_id, input_cid)),
      ("input_contract", input_body),
      (
        "output_schema",
        local_file_store_contract_reference(output_id, output_cid),
      ),
      ("permissions", ["files.write"]),
      ("preview", { "strength": "exact" }),
      ("outcome", "synchronous".to_json()),
      ("idempotency", { "support": "unsupported" }),
      ("reversibility", "unknown".to_json()),
      ("atomicity", "single_target".to_json()),
    ],
    "contract_cid",
    limits,
  )
  { input, input_cid, output, output_cid, body, cid, id, }
}

///|
pub struct LocalFileStoreTargetIdentity {
  root : String
  target_ref : String
  resource_identity_cid : String
  mapping_cid : String
  command_cid : String
}

///|
priv struct LocalFileStoreDeclaration {
  target : LocalFileStoreTargetIdentity
  command_wire : String
  mapping_wire : String
  identity_wire : String
}

///|
/// Borrow the exact identity emitted into the declaration. This is checked
/// metadata for a physical installer, not the installed owner or a grant.
pub fn local_file_store_target_identity(
  declaration : RowDeclaration,
) -> LocalFileStoreTargetIdentity? {
  declaration.local_file_store.map(store => store.target)
}

///|
/// Borrow the three immutable wires of a declaration issued for the original
/// Local File root. Views projected from arbitrary metadata have no STORE.
pub fn local_file_store_declaration_wires(
  declaration : RowDeclaration,
) -> (String, String, String)? {
  declaration.local_file_store.map(store => {
    (store.command_wire, store.mapping_wire, store.identity_wire)
  })
}

///|
fn local_file_store_declaration(
  connection : String,
  root : String,
  catalog_cid : String,
  manifest_cid : String,
  command : LocalFileStoreCommand,
  limits : RowDeclarationLimits,
) -> LocalFileStoreDeclaration raise @encode.EncodeFailure {
  let target_ref = "connector://" + connection + "/files"
  let identity : Json = {
    "boundary_topology": "connector_connection",
    "collection_identity": { "root": root.to_json() },
    "provider_namespace": "local",
    "resource_kind": "file_collection",
    "target_ref": target_ref.to_json(),
    "version": "actql.collection_resource_identity/0.1",
  }
  let resource_identity_cid = canonical_cid(identity, limits)
  let schema : Json = {
    "additional_properties": false,
    "fields": local_file_store_fields(),
    "nullable": false,
    "type": "object",
  }
  let permissions : Json = ["files.write"]
  let writable_fields : Json = ["content", "overwrite", "path"]
  let required_fields : Json = ["content", "path"]
  let permission_rules = Json::array(
    [required_fields, writable_fields].map(write_fields => {
      "effect_kind": "create",
      "permissions": permissions,
      "selector_class": "none",
      "write_fields": write_fields,
    }),
  )
  let row_mapping : Json = {
    "content": { "field": "content", "null_behavior": "reject" },
    "overwrite": { "field": "overwrite", "null_behavior": "reject" },
    "path": { "field": "path", "null_behavior": "reject" },
  }
  let (mapping, mapping_cid) = seal(
    [
      ("schema", "actql.mapping_contract/0.1".to_json()),
      (
        "mapping_ref",
        ("mapping:" + connection + ".local.files.store.v1").to_json(),
      ),
      ("version", "local/0.1".to_json()),
      ("target_ref", target_ref.to_json()),
      ("connector_manifest_cid", manifest_cid.to_json()),
      ("resource_identity_cid", resource_identity_cid.to_json()),
      ("target_schema_identity", canonical_cid(schema, limits).to_json()),
      ("target_schema", schema),
      ("primary_identity", Json::null()),
      ("writable_fields", writable_fields),
      ("required_fields", required_fields),
      ("conversions", []),
      ("permission_rules", permission_rules),
      ("required_permissions", permissions),
      ("minimum_approval", "required".to_json()),
      ("row_mapping", row_mapping),
      (
        "store_command",
        {
          "catalog_cid": catalog_cid.to_json(),
          "command_contract_cid": command.cid.to_json(),
          "command_ref": command.id.to_json(),
        },
      ),
    ],
    "mapping_contract_cid",
    limits,
  )
  {
    target: {
      root,
      target_ref,
      resource_identity_cid,
      mapping_cid,
      command_cid: command.cid,
    },
    command_wire: canonical_text(command.body, limits),
    mapping_wire: canonical_text(mapping, limits),
    identity_wire: canonical_text(identity, limits),
  }
}

///|
// The fixed canonical bodies below have no variable spelling other than the
// validated ASCII connector ID and the escaped Root in collection_identity.
// Count value nodes (including object and array nodes) and writer depth.
// The Catalog owns the input, output and Command subtrees; Mapping and
// identity are detached members with their own writers and backing.
fn local_file_store_construction_inventory(
  connector_width : Int64,
  root : String,
  parts : Array[@execution.PreparationRepresentationUnits],
) -> (Int64, Int64, Int64)? {
  guard @encode.quoted_string_construction_extent(root) is Some((root_bytes, _)) else {
    return None
  }
  let input = 423L + connector_width
  let output = 282L + connector_width
  let command = 1017L + 4L * connector_width
  let mapping = 1649L + 3L * connector_width
  let identity = 226L + connector_width + root_bytes - 2L
  for
    (bytes, nodes, depth) in [
      (input, 21L, 5),
      (output, 11L, 3),
      (command, 41L, 5),
      (mapping, 67L, 5),
      (identity, 8L, 3),
    ] {
    if !relation_restore_add(
        parts,
        relation_restore_emission(bytes, nodes, depth, true),
      ) {
      return None
    }
  }
  guard relation_construction_json_forest(2L * 67L + 8L) is Some(detached) else {
    return None
  }
  parts.push(relation_construction_collection_units(detached))
  // The target schema is the 14-node, depth-four Mapping subtree. It is
  // hashed directly and does not produce another text or Mapping writer.
  guard @encode.hash_writer_construction_inventory(14, 4) is Some(schema_hash) else {
    return None
  }
  parts.push({
    record_headers: schema_hash.record_headers,
    reference_slots: schema_hash.reference_slots,
    scalar_words: schema_hash.scalar_words,
    owned_utf16_units: schema_hash.owned_utf16_units,
    owned_wire_bytes: schema_hash.owned_wire_bytes,
  })
  parts.push({
    record_headers: 25L,
    reference_slots: 70L,
    scalar_words: 16L,
    // The target identity borrows the Root and retains the original target
    // reference and three fixed-width CIDs past the wire writers.
    owned_utf16_units: 17L * connector_width +
    512L +
    mapping +
    identity +
    "connector:///files".length().to_int64() +
    3L * 71L,
    owned_wire_bytes: 0L,
  })
  // Two new contracts in the nonempty array, plus one first Command.
  Some(
    (input + output + command + 2L, 21L + 11L + 41L, input + output + command),
  )
}

///|
/// The raw Local metadata export uses the same bound as its Node consumer.
let local_file_declaration_export_max_bytes : Int = 131072

///|
fn local_file_export_string_field(
  writer : @encode.Writer,
  name : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.string_value(writer, value)
}

///|
fn local_file_export_string_array(
  writer : @encode.Writer,
  name : String,
  values : Array[String],
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, name)
  @encode.begin_array(writer)
  for value in values {
    @encode.string_value(writer, value)
  }
  @encode.end_array(writer)
}

///|
fn local_file_evidence_export_bounds(view : RowDeclaredView) -> (Int64, Int64) {
  let ref_units = view.source_ref.length().to_int64()
  let cid_units = view.view_cid.length().to_int64()
  let schema_units = ref_units +
    2L * cid_units +
    view.carrier_schema_cid.length().to_int64() +
    view.data_policy_cid.length().to_int64() +
    view.classification.length().to_int64()
  // Each of the two existing evidence writers bounds output at 4096.
  // Their fixed keys, punctuation, literals and up to two 71-unit profile
  // CIDs are included in their separate fixed envelopes.
  let schema = Int64::min(4096L, 512L + 6L * schema_units)
  let capability = Int64::min(4096L, 768L + 6L * (ref_units + 2L * cid_units))
  (schema, capability)
}

///|
fn local_file_declaration_export_geometry(
  declaration : RowDeclaration,
  command : String,
) -> (Int, Int, Int, Int64) {
  let mut units = declaration.connector_id.length().to_int64() +
    declaration.connector_registration.length().to_int64() +
    declaration.connector_version.length().to_int64() +
    declaration.catalog.length().to_int64() +
    declaration.catalog_cid.length().to_int64() +
    declaration.manifest_entry.length().to_int64() +
    declaration.manifest_entry_cid.length().to_int64() +
    command.length().to_int64()
  let mut array_items = 0L
  for wires in [declaration.contracts, declaration.view_bodies] {
    array_items += wires.length().to_int64()
    for wire in wires {
      units += wire.length().to_int64()
    }
  }
  let views = declaration.views.length().to_int64()
  let mut fields = 0L
  let mut evidence = 0L
  let mut evidence_peak = 0L
  for view in declaration.views {
    units += view.resource.length().to_int64() +
      view.source_ref.length().to_int64() +
      view.view_cid.length().to_int64() +
      view.carrier_schema_cid.length().to_int64() +
      view.data_policy_cid.length().to_int64()
    fields += view.fields.length().to_int64()
    for field in view.fields {
      units += field.length().to_int64()
    }
    let (schema, capability) = local_file_evidence_export_bounds(view)
    evidence += schema + capability
    evidence_peak = Int64::max(evidence_peak, Int64::max(schema, capability))
  }
  let envelope = "{\"connector_id\":\"\",\"connector_registration\":\"\",\"connector_version\":\"\",\"catalog\":\"\",\"catalog_cid\":\"\",\"contracts\":[],\"views\":[],\"view_bodies\":[],\"manifest_entry\":\"\",\"manifest_entry_cid\":\"\",\"evidence_schemas\":[],\"evidence_capabilities\":[],\"command_bodies\":[\"\"]}"
  let view = "{\"resource\":\"\",\"source_ref\":\"\",\"view_cid\":\"\",\"fields\":[],\"carrier_schema_cid\":\"\",\"data_policy_cid\":\"\"}"
  // Strings may need up to six output bytes per original UTF16 unit. An
  // evidence String is escaped again in the outer object. Count a comma
  // even for the first item. Each view contributes two evidence Strings.
  let bytes = envelope.length().to_int64() +
    views * (view.length().to_int64() + 1L) +
    3L * (array_items + fields + 2L * views) +
    6L * (units + evidence)
  let nodes = 15L + array_items + fields + 9L * views
  let limit = local_file_declaration_export_max_bytes.to_int64()
  (
    Int64::min(bytes, limit).to_int(),
    Int64::min(nodes, limit).to_int(),
    evidence_peak.to_int(),
    evidence,
  )
}

///|
/// Quote the bounded wire and all evidence Strings from this issued original.
/// The three STORE Strings are borrowed; their returned carrier is included.
pub fn local_file_declaration_export_capacity(
  declaration : RowDeclaration,
) -> Result[@execution.ExecutionCapacity, RowHostIssue] {
  guard local_file_store_declaration_wires(declaration) is Some((command, _, _)) else {
    return Err(ForeignDeclaration)
  }
  let (bytes, nodes, evidence_peak, evidence) = local_file_declaration_export_geometry(
    declaration, command,
  )
  let views = declaration.views.length().to_int64()
  guard relation_construction_writer_units(bytes, nodes, 4) is Some(outer) &&
    relation_construction_writer_units(evidence_peak, 9, 2)
    is Some(member_writer) &&
    @execution.compose_preparation_representation([
      outer,
      member_writer,
      {
        // Two evidence vectors/growth, one active member's fields and keys,
        // the STORE tuple/array, Result and returned Host descriptor controls.
        record_headers: 80L + 2L * views,
        reference_slots: 144L + 8L * views,
        scalar_words: 96L + 2L * views,
        owned_utf16_units: evidence,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(workspace) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: 8L,
        reference_slots: 16L,
        scalar_words: 8L,
        owned_utf16_units: bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
      workspace,
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(capacity) else {
    return Err(InvalidSpecification)
  }
  Ok(capacity)
}

///|
/// Emit only the closed Local declaration wire, including the sealed STORE
/// command and the existing Check Environment evidence from the same issuer.
pub fn local_file_declaration_export(
  declaration : RowDeclaration,
) -> Result[String, RowHostIssue] {
  guard local_file_store_declaration_wires(declaration) is Some((command, _, _)) else {
    return Err(ForeignDeclaration)
  }
  let (bytes, nodes, _, _) = local_file_declaration_export_geometry(
    declaration, command,
  )
  try {
    let (schemas, capabilities) = row_declaration_evidence_members(declaration)
    let writer = @encode.writer(bytes, nodes, 4)
    @encode.begin_object(writer)
    local_file_export_string_field(
      writer,
      "connector_id",
      declaration.connector_id,
    )
    local_file_export_string_field(
      writer,
      "connector_registration",
      declaration.connector_registration,
    )
    local_file_export_string_field(
      writer,
      "connector_version",
      declaration.connector_version,
    )
    local_file_export_string_field(writer, "catalog", declaration.catalog)
    local_file_export_string_field(
      writer,
      "catalog_cid",
      declaration.catalog_cid,
    )
    local_file_export_string_array(writer, "contracts", declaration.contracts)
    @encode.key(writer, "views")
    @encode.begin_array(writer)
    for view in declaration.views {
      @encode.begin_object(writer)
      local_file_export_string_field(writer, "resource", view.resource)
      local_file_export_string_field(writer, "source_ref", view.source_ref)
      local_file_export_string_field(writer, "view_cid", view.view_cid)
      local_file_export_string_array(writer, "fields", view.fields)
      local_file_export_string_field(
        writer,
        "carrier_schema_cid",
        view.carrier_schema_cid,
      )
      local_file_export_string_field(
        writer,
        "data_policy_cid",
        view.data_policy_cid,
      )
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    local_file_export_string_array(
      writer,
      "view_bodies",
      declaration.view_bodies,
    )
    local_file_export_string_field(
      writer,
      "manifest_entry",
      declaration.manifest_entry,
    )
    local_file_export_string_field(
      writer,
      "manifest_entry_cid",
      declaration.manifest_entry_cid,
    )
    local_file_export_string_array(writer, "evidence_schemas", schemas)
    local_file_export_string_array(
      writer, "evidence_capabilities", capabilities,
    )
    local_file_export_string_array(writer, "command_bodies", [command])
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidSpecification)
  }
}
