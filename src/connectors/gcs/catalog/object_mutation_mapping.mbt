// Mapping DATA for an already selected mutation binding. This does not admit
// a Catalog, issue a read/write grant, or authenticate an installed original.

///|
fn mutation_mapping_catalog(
  binding : ObjectMutationBinding,
  declared_wire : String,
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[(String, String), ObjectUploadDeclarationIssue] {
  let declared = match upload_read_declaration_json(declared_wire, limits) {
    Ok(Object(value)) => value
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  guard declared.get("connector_id") == Some(connector_id.to_json()) &&
    declared.get("connector_registration") == Some("gcs".to_json()) &&
    declared.get("connector_version") == Some("gcs/0.1".to_json()) &&
    declared.get("catalog_cid") == Some(binding.catalog_cid.to_json()) &&
    declared.get("catalog") is Some(String(catalog_wire)) &&
    declared.get("contracts") is Some(Array(contract_wires)) &&
    declared.get("views") is Some(Array(views)) &&
    declared.get("manifest_entry") is Some(String(manifest_wire)) &&
    declared.get("manifest_entry_cid") is Some(String(manifest_cid)) else {
    return Err(InvalidDeclaration)
  }
  let catalog = match upload_read_declaration_json(catalog_wire, limits) {
    Ok(Object(value)) => value
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  guard catalog.length() == 7 &&
    catalog.get("schema") == Some("actql.connector_catalog/0.1".to_json()) &&
    catalog.get("connector_id") == Some(connector_id.to_json()) &&
    catalog.get("connector_version") == Some("gcs/0.1".to_json()) &&
    catalog.get("catalog_cid") == Some(binding.catalog_cid.to_json()) &&
    catalog.get("commands") is Some(Array(_)) &&
    catalog.get("contracts") is Some(Array(contracts)) &&
    catalog.get("source_views") is Some(Array(source_views)) &&
    contracts.length() == contract_wires.length() else {
    return Err(InvalidDeclaration)
  }
  catalog.remove("catalog_cid") |> ignore
  match upload_declaration_json(Json::object(catalog), limits) {
    Ok(wire) if collection_cid(wire) == binding.catalog_cid => ()
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  for index in 0..<contracts.length() {
    guard contract_wires[index] is String(wire) else {
      return Err(InvalidDeclaration)
    }
    match upload_read_declaration_json(wire, limits) {
      Ok(value) if value == contracts[index] => ()
      Ok(_) => return Err(InvalidDeclaration)
      Err(issue) => return Err(issue)
    }
  }
  let manifest = match upload_read_declaration_json(manifest_wire, limits) {
    Ok(Object(value)) => value
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  if manifest.length() != 3 ||
    manifest.get("connector") != Some("gcs".to_json()) ||
    manifest.get("connector_id") != Some(connector_id.to_json()) ||
    manifest.get("connector_version") != Some("gcs/0.1".to_json()) {
    return Err(InvalidDeclaration)
  }
  match upload_declaration_json(Json::object(manifest), limits) {
    Ok(wire) if collection_cid(wire) == manifest_cid => ()
    Ok(_) => return Err(InvalidDeclaration)
    Err(issue) => return Err(issue)
  }
  let target = "connector://" + connector_id + "/objects"
  // The selected locator must name a member of this same complete Catalog,
  // not just an equal detached CID. Common still admits its full role graph.
  let mut selected = None
  for view in views {
    guard view is Object(fields) else { return Err(InvalidDeclaration) }
    if fields.get("source_ref") == Some((target + "#records").to_json()) {
      guard selected is None && fields.get("view_cid") is Some(String(cid)) else {
        return Err(InvalidDeclaration)
      }
      selected = Some(cid)
    }
  }
  guard selected is Some(cid) else { return Err(InvalidBinding) }
  let mut matches = 0
  for view in source_views {
    guard view is Object(fields) else { return Err(InvalidDeclaration) }
    if fields.get("contract_cid") == Some(cid.to_json()) &&
      fields.get("connector_id") == Some(connector_id.to_json()) &&
      fields.get("connector_version") == Some("gcs/0.1".to_json()) &&
      fields.get("resource_kind") == Some("file".to_json()) &&
      fields.get("view_id") == Some("records".to_json()) {
      matches += 1
    }
  }
  if matches != 1 {
    return Err(InvalidDeclaration)
  }
  Ok((target, manifest_cid))
}

///|
// Keep authored nullable fields distinct from the effective request projection.
// Full-diff Preview/current/permission/capture/restore remain Common/Host work;
// emitting this candidate does not enable an otherwise unavailable send path.
pub fn object_mutation_mapping_json(
  binding : ObjectMutationBinding,
  declared_wire : String,
  connector_id : String,
  limits : ObjectUploadDeclarationLimits,
) -> Result[String, ObjectUploadDeclarationIssue] {
  if limits.max_bytes < 1 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidBinding)
  }
  let suffix = match binding.kind {
    PatchMetadata => "metadata"
    DeleteObject => "delete"
  }
  let mapping_ref = "mapping:" + connector_id + ".gcs.objects." + suffix + ".v1"
  if !@reference.valid_mapping_ref(mapping_ref) {
    return Err(InvalidBinding)
  }
  let required = match binding.kind {
    PatchMetadata => "storage.objects.update"
    DeleteObject => "storage.objects.delete"
  }
  if !binding.permissions.contains(required) ||
    !binding.permissions.contains("storage.objects.get") {
    return Err(InvalidBinding)
  }
  let (target, manifest_cid) = match
    mutation_mapping_catalog(binding, declared_wire, connector_id, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema : Json = {
    "type": "object",
    "nullable": false,
    "additional_properties": false,
    "fields": {
      "name": { "type": "string", "nullable": false },
      "content_type": { "type": "string", "nullable": true },
      "metadata": { "type": "json", "nullable": true },
    },
  }
  let schema_cid = match upload_declaration_json(schema, limits) {
    Ok(wire) => collection_cid(wire)
    Err(issue) => return Err(issue)
  }
  let identity : Json = {
    "version": "actql.resource_identity/0.1",
    "provider_namespace": "gcs",
    "resource_kind": "file",
    "provider_id_field": "name",
    "output_field": "name",
    "boundary_topology": "connector_connection",
  }
  let identity_cid = match upload_declaration_json(identity, limits) {
    Ok(wire) => collection_cid(wire)
    Err(issue) => return Err(issue)
  }
  let writable = match binding.kind {
    PatchMetadata => ["content_type", "metadata"]
    DeleteObject => []
  }
  let field_sets = match binding.kind {
    PatchMetadata =>
      [["content_type"], ["metadata"], ["content_type", "metadata"]]
    DeleteObject => [[]]
  }
  let permissions = Json::array(
    binding.permissions.map(value => value.to_json()),
  )
  let rules : Array[Json] = field_sets.map(names => {
    "effect_kind": (match binding.kind {
      PatchMetadata => "update"
      DeleteObject => "delete"
    }).to_json(),
    "selector_class": "id",
    "write_fields": Json::array(names.map(name => name.to_json())),
    "permissions": permissions,
  })
  let mapping : Json = {
    "schema": "actql.mapping_contract/0.1",
    "mapping_ref": mapping_ref.to_json(),
    "version": "gcs/0.1",
    "target_ref": target.to_json(),
    "connector_manifest_cid": manifest_cid.to_json(),
    "resource_identity_cid": identity_cid.to_json(),
    "target_schema_identity": schema_cid.to_json(),
    "target_schema": schema,
    "primary_identity": "name",
    "writable_fields": Json::array(writable.map(name => name.to_json())),
    "required_fields": [],
    "conversions": [],
    "permission_rules": Json::array(rules),
    "required_permissions": permissions,
    "minimum_approval": "required",
    "row_mapping": {},
  }
  match upload_declaration_seal(mapping, "mapping_contract_cid", limits) {
    Ok(value) => upload_declaration_json(value, limits)
    Err(issue) => Err(issue)
  }
}
