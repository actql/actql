// Connector-owned static declarations, not a ResourceRef issuer or an upload
// permit. The existing Common Catalog/Command owner admits their exact roles.

///|
pub(all) struct ObjectUploadDeclarationLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum ObjectUploadDeclarationIssue {
  InvalidBinding
  InvalidDeclaration
  ConflictingCommand
  CapacityExceeded
} derive(Eq, Debug)

///|
fn upload_declaration_json(
  value : Json,
  limits : ObjectUploadDeclarationLimits,
) -> Result[String, ObjectUploadDeclarationIssue] {
  match
    collection_json(value, {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => Ok(value)
    Err(_) => Err(CapacityExceeded)
  }
}

///|
fn upload_declaration_seal(
  value : Json,
  field : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[Json, ObjectUploadDeclarationIssue] {
  let wire = match upload_declaration_json(value, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard value is Object(fields) else { return Err(InvalidDeclaration) }
  fields[field] = collection_cid(wire).to_json()
  Ok(Json::object(fields))
}

///|
fn upload_declaration_reference(value : Json) -> Json {
  guard value is Object(fields) else { abort("internal upload envelope") }
  { "id": fields["id"], "version": fields["version"], "cid": fields["cid"] }
}

///|
fn upload_command_bundle(
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[Json, ObjectUploadDeclarationIssue] {
  if limits.max_bytes < 1 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidBinding)
  }
  let command_id = "command:" + connector_id + ".gcs.upload.v1"
  if connector_id.is_empty() ||
    @scalar.admit_utf8_length(connector_id, 128) is Err(_) ||
    !@reference.valid_command_ref(command_id) {
    return Err(InvalidBinding)
  }
  // Presence belongs to Command input, not the general Object ValueContract.
  // Omission does not synthesize false, NULL, a default media type or a Ref.
  let input_body : Json = {
    "additional_properties": false,
    "fields": {
      "content": { "type": "content_ref", "nullable": false },
      "content_type": { "type": "string", "nullable": false },
      "name": { "type": "string", "nullable": false },
      "overwrite": { "type": "boolean", "nullable": false },
    },
    "required_fields": ["content", "name"],
  }
  let input = match
    upload_declaration_seal(
      {
        "schema": "actql.contract/0.1",
        "id": (connector_id + ".gcs.upload.command_input").to_json(),
        "version": "gcs/0.1",
        "kind": "command_input",
        "body": input_body,
      },
      "cid",
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = match
    upload_declaration_seal(
      {
        "schema": "actql.contract/0.1",
        "id": (connector_id + ".gcs.upload.command_output").to_json(),
        "version": "gcs/0.1",
        "kind": "command_output",
        "body": {
          "type": "object",
          "nullable": false,
          "additional_properties": false,
          "fields": {},
        },
      },
      "cid",
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let command = match
    upload_declaration_seal(
      {
        "schema": "actql.command_contract/0.1",
        "command_id": command_id.to_json(),
        "connector_id": connector_id.to_json(),
        "version": "gcs/0.1",
        "target": {
          "resource_kind": "file_collection",
          "cardinality": "single",
        },
        "input_schema": upload_declaration_reference(input),
        "input_contract": input_body,
        "output_schema": upload_declaration_reference(output),
        // This fixed Command supports both create and explicit replacement;
        // its declared requirements cover that complete selected operation.
        // They are requirements, not newly issued or inferred permissions.
        "permissions": [
          "storage.objects.create", "storage.objects.delete", "storage.objects.get",
        ],
        "preview": { "strength": "exact" },
        "outcome": "synchronous",
        "idempotency": { "support": "unsupported" },
        "reversibility": "unknown",
        "atomicity": "single_target",
      },
      "contract_cid",
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ "command": command, "contracts": [input, output] })
}

///|
pub fn object_upload_command_json(
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[String, ObjectUploadDeclarationIssue] {
  match upload_command_bundle(connector_id, limits) {
    Ok(value) => upload_declaration_json(value, limits)
    Err(issue) => Err(issue)
  }
}

///|
fn upload_read_declaration_json(
  wire : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[Json, ObjectUploadDeclarationIssue] {
  if @scalar.admit_utf8_length(wire, limits.max_bytes) is Err(_) {
    return Err(CapacityExceeded)
  }
  match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(_) => ()
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => CapacityExceeded
          _ => InvalidDeclaration
        },
      )
  }
  Ok(@json.parse(wire)) catch {
    _ => Err(InvalidDeclaration)
  }
}

///|
fn upload_member_cid(value : Json, field : String) -> String? {
  guard value is Object(fields) &&
    fields.get(field) is Some(String(cid)) &&
    mutation_cid(cid) else {
    return None
  }
  Some(cid)
}

///|
fn upload_sorted_members(
  values : Array[Json],
  field : String,
) -> Result[Array[Json], ObjectUploadDeclarationIssue] {
  let members : Map[String, Json] = Map([])
  let keys = []
  for value in values {
    guard upload_member_cid(value, field) is Some(cid) && !members.contains(cid) else {
      return Err(InvalidDeclaration)
    }
    members[cid] = value
    keys.push(cid)
  }
  keys.sort()
  Ok(keys.map(key => members[key]))
}

///|
// Extend the exact original source declaration as DATA, preserving every
// SourceView/evidence/manifest field. Common must still admit the full Catalog
// and registry in its original environment; this projection cannot issue Ref
// custody, currentness, approval or a write capability.
pub fn object_upload_catalog_json(
  declared_wire : String,
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[String, ObjectUploadDeclarationIssue] {
  let bundle = match upload_command_bundle(connector_id, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let declared = match upload_read_declaration_json(declared_wire, limits) {
    Ok(Object(value)) => value
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  guard declared.get("catalog") is Some(String(catalog_wire)) else {
    return Err(InvalidDeclaration)
  }
  let catalog = match upload_read_declaration_json(catalog_wire, limits) {
    Ok(Object(value)) => value
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  guard bundle is Object(bundle) &&
    bundle.get("command") is Some(command) &&
    bundle.get("contracts") is Some(Array(additional)) &&
    declared.get("connector_id") == Some(connector_id.to_json()) &&
    declared.get("connector_registration") == Some("gcs".to_json()) &&
    declared.get("connector_version") == Some("gcs/0.1".to_json()) &&
    catalog.length() == 7 &&
    catalog.get("schema") == Some("actql.connector_catalog/0.1".to_json()) &&
    catalog.get("connector_id") == Some(connector_id.to_json()) &&
    catalog.get("connector_version") == Some("gcs/0.1".to_json()) &&
    catalog.get("commands") is Some(Array(commands)) &&
    catalog.get("contracts") is Some(Array(original_contracts)) &&
    catalog.get("source_views") is Some(Array(_)) &&
    upload_member_cid(Json::object(catalog), "catalog_cid")
    is Some(original_cid) &&
    declared.get("catalog_cid") == Some(original_cid.to_json()) &&
    declared.get("contracts") is Some(Array(contract_wires)) else {
    return Err(InvalidDeclaration)
  }
  catalog.remove("catalog_cid") |> ignore
  match upload_declaration_json(Json::object(catalog), limits) {
    Ok(wire) if collection_cid(wire) == original_cid => ()
    _ => return Err(InvalidDeclaration)
  }
  if contract_wires.length() != original_contracts.length() {
    return Err(InvalidDeclaration)
  }
  // Validate the supplied detached registry against the same complete Catalog
  // members before adding anything. Hash strings alone do not establish it.
  let contracts = []
  for index in 0..<contract_wires.length() {
    guard contract_wires[index] is String(wire) &&
      upload_read_declaration_json(wire, limits) is Ok(value) else {
      return Err(InvalidDeclaration)
    }
    if value != original_contracts[index] {
      return Err(InvalidDeclaration)
    }
    contracts.push(value)
  }
  guard command is Object(command_fields) else {
    return Err(InvalidDeclaration)
  }
  let command_id = command_fields["command_id"]
  let merged_commands = []
  let mut present = false
  for old in commands {
    guard old is Object(fields) else { return Err(InvalidDeclaration) }
    if fields.get("command_id") == Some(command_id) {
      if old != command {
        return Err(ConflictingCommand)
      }
      present = true
    }
    merged_commands.push(old)
  }
  if !present {
    merged_commands.push(command)
  }
  for envelope in additional {
    guard envelope is Object(fields) else { return Err(InvalidDeclaration) }
    let mut present = false
    for old in contracts {
      guard old is Object(old_fields) else { return Err(InvalidDeclaration) }
      if old_fields.get("id") == fields.get("id") &&
        old_fields.get("version") == fields.get("version") {
        if old != envelope {
          return Err(ConflictingCommand)
        }
        present = true
      }
    }
    if !present {
      contracts.push(envelope)
    }
  }
  let contracts = match upload_sorted_members(contracts, "cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let commands = match upload_sorted_members(merged_commands, "contract_cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  catalog["contracts"] = Json::array(contracts)
  catalog["commands"] = Json::array(commands)
  let completed = match
    upload_declaration_seal(Json::object(catalog), "catalog_cid", limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  declared["catalog_cid"] = upload_member_cid(completed, "catalog_cid")
    .unwrap()
    .to_json()
  declared["catalog"] = match upload_declaration_json(completed, limits) {
    Ok(value) => value.to_json()
    Err(issue) => return Err(issue)
  }
  let wires = []
  for contract in contracts {
    match upload_declaration_json(contract, limits) {
      Ok(value) => wires.push(value.to_json())
      Err(issue) => return Err(issue)
    }
  }
  declared["contracts"] = Json::array(wires)
  let command_wires = []
  for command in commands {
    match upload_declaration_json(command, limits) {
      Ok(value) => command_wires.push(value.to_json())
      Err(issue) => return Err(issue)
    }
  }
  declared["command_bodies"] = Json::array(command_wires)
  upload_declaration_json(Json::object(declared), limits)
}

///|
// Published collection Mapping DATA, not a synthetic Result row or Ref issuer.
pub fn object_upload_mapping_json(
  binding : ObjectCollectionBinding,
  declared_wire : String,
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[String, ObjectUploadDeclarationIssue] {
  let complete = match
    object_upload_catalog_json(declared_wire, connector_id, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard upload_read_declaration_json(complete, limits) is Ok(Object(declared)) &&
    declared.get("catalog_cid") is Some(String(catalog_cid)) &&
    declared.get("manifest_entry") is Some(String(manifest_wire)) &&
    declared.get("manifest_entry_cid") is Some(String(manifest_cid)) &&
    upload_read_declaration_json(manifest_wire, limits) is Ok(manifest) &&
    manifest is Object(manifest_fields) &&
    manifest_fields.length() == 3 &&
    manifest_fields.get("connector") == Some("gcs".to_json()) &&
    manifest_fields.get("connector_id") == Some(connector_id.to_json()) &&
    manifest_fields.get("connector_version") == Some("gcs/0.1".to_json()) &&
    upload_read_declaration_json(binding.resource_wire, limits)
    is Ok(Object(resource)) &&
    resource.get("boundary_cid") == Some(catalog_cid.to_json()) &&
    resource.get("resource_kind") == Some("file_collection".to_json()) &&
    binding.target_ref == "connector://" + connector_id + "/objects" else {
    return Err(InvalidBinding)
  }
  match upload_declaration_json(manifest, limits) {
    Ok(wire) if collection_cid(wire) == manifest_cid => ()
    _ => return Err(InvalidBinding)
  }
  guard upload_command_bundle(connector_id, limits) is Ok(Object(bundle)) &&
    bundle["command"] is Object(command) &&
    command["input_contract"] is Object(input) &&
    command["permissions"] is Array(permissions) else {
    return Err(InvalidDeclaration)
  }
  let schema : Json = {
    "type": "object",
    "nullable": false,
    "additional_properties": false,
    "fields": input["fields"],
  }
  let schema_cid = match upload_declaration_json(schema, limits) {
    Ok(wire) => collection_cid(wire)
    Err(issue) => return Err(issue)
  }
  let row_mapping : Map[String, Json] = Map([])
  let writable = ["content", "content_type", "name", "overwrite"]
  for name in writable {
    row_mapping[name] = { "field": name.to_json(), "null_behavior": "reject" }
  }
  let rules : Array[Json] = []
  for
    names in [
      ["content", "name"],
      ["content", "content_type", "name"],
      ["content", "name", "overwrite"],
      ["content", "content_type", "name", "overwrite"],
    ] {
    rules.push({
      "effect_kind": "create",
      "selector_class": "none",
      "write_fields": Json::array(names.map(name => name.to_json())),
      "permissions": Json::array(permissions),
    })
  }
  let mapping_ref = "mapping:" + connector_id + ".gcs.objects.upload.v1"
  if !@reference.valid_mapping_ref(mapping_ref) {
    return Err(InvalidBinding)
  }
  let mapping : Json = {
    "schema": "actql.mapping_contract/0.1",
    "mapping_ref": mapping_ref.to_json(),
    "version": "gcs/0.1",
    "target_ref": binding.target_ref.to_json(),
    "connector_manifest_cid": manifest_cid.to_json(),
    "resource_identity_cid": binding.identity_cid.to_json(),
    "target_schema_identity": schema_cid.to_json(),
    "target_schema": schema,
    "primary_identity": Json::null(),
    "writable_fields": Json::array(writable.map(name => name.to_json())),
    "required_fields": input["required_fields"],
    "conversions": [],
    "permission_rules": Json::array(rules),
    "required_permissions": Json::array(permissions),
    "minimum_approval": "required",
    "row_mapping": Json::object(row_mapping),
    "store_command": {
      "catalog_cid": catalog_cid.to_json(),
      "command_ref": command["command_id"],
      "command_contract_cid": command["contract_cid"],
    },
  }
  match upload_declaration_seal(mapping, "mapping_contract_cid", limits) {
    Ok(value) => upload_declaration_json(value, limits)
    Err(issue) => Err(issue)
  }
}
