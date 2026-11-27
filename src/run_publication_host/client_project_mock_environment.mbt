///|
/// Canonical encoding for the same installed Mock declarations and evidence.
/// This supplies identity data before the existing admission and policy checks.
pub fn client_project_mock_wire(
  value : Json,
) -> Result[String, @row_host.RowHostIssue] {
  try {
    let canonical = @canonical.from_json(
      value,
      400000,
      64,
      4000000,
      data_keys=true,
    )
    Ok(@canonical.stringify_value(canonical, 4000000, 400000, 64))
  } catch {
    _ => Err(@row_host.RowHostIssue::InvalidSpecification)
  }
}

///|
// Canonical DATA assembly only. Every entry is still admitted by the same
// ordinary Environment/Catalog owner; exact duplicate bodies coalesce, while
// conflicting selectors remain present for its original typed refusal.
fn client_project_mock_members(
  values : Array[Json],
) -> Result[Json, @row_host.RowHostIssue] {
  let members : Array[(String, String, Json)] = []
  for value in values {
    let wire = match client_project_mock_wire(value) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !members.any(entry => entry.1 == wire) {
      members.push(("sha256:" + @sha.hex(@utf8.encode(wire)), wire, value))
    }
  }
  members.sort_by((left, right) => {
    if left.0 < right.0 {
      -1
    } else if left.0 == right.0 {
      0
    } else {
      1
    }
  })
  Ok(Json::array(members.map(entry => entry.2)))
}

///|
priv suberror InvalidClientProjectMockEnvironment {
  InvalidClientProjectMockEnvironment
}

///|
fn client_project_mock_array(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise InvalidClientProjectMockEnvironment {
  guard fields.get(key) is Some(Array(values)) else {
    raise InvalidClientProjectMockEnvironment
  }
  values.copy()
}

///|
/// Merge the evidence of the same selected Mock Source declarations into the
/// original checker environment. Adapter ports project existing file-read
/// capabilities and UPDATE bodies. This constructs the wire and its CID;
/// the original checker still admits it under the installed Host profile.
pub fn[T] assemble_client_project_mock_environment(
  base : @checked.CheckEnvironment,
  sources : Array[T],
  lookup_policy : () -> Json?,
  declaration : (T) -> @row_host.RowDeclaration,
  file_capabilities : (T, String) -> Iter[String],
  write_bodies : (T) -> Iter[String],
) -> (String, String)? {
  try {
    let writer = @encode.writer(4000000, 400000, 64)
    @environment.emit(@checked.checking_environment_wire(base), writer)
    guard @json.parse(@encode.finish(writer)) is Object(body) else {
      return None
    }
    if lookup_policy() is Some(lookup) {
      guard body.get("host_policy_profile") is Some(Object(policy)) else {
        return None
      }
      // Respect an explicitly installed policy and fill only the missing
      // component. This never supplies a per-Request authorization decision.
      if !policy.contains("lookup_execution") {
        policy["lookup_execution"] = lookup
      }
    }
    let catalogs = client_project_mock_array(body, "connector_catalogs")
    let contracts = client_project_mock_array(body, "contract_registry")
    let views = client_project_mock_array(body, "source_views")
    let schemas = client_project_mock_array(body, "schema_snapshots")
    let capabilities = client_project_mock_array(body, "connector_capabilities")
    let mappings = client_project_mock_array(body, "mapping_contracts")
    let commands = client_project_mock_array(body, "command_contracts")
    let manifest = match body.get("connector_manifest") {
      Some(Object(fields)) => fields
      None =>
        Map([
          ("version", Json::string("actql-connectors/0.1")),
          ("connectors", Json::array([])),
        ])
      _ => return None
    }
    let entries = client_project_mock_array(manifest, "connectors")
    for source in sources {
      let original = declaration(source)
      catalogs.push(@json.parse(original.catalog))
      // A Local File Catalog includes an original command even when its
      // Check publishes only reads. The registry must contain that same
      // command; only a separately published target could make it usable.
      if @row_host.local_file_store_declaration_wires(original)
        is Some((command, _, _)) {
        commands.push(@json.parse(command))
      }
      for wire in original.contracts {
        contracts.push(@json.parse(wire))
      }
      for wire in original.view_bodies {
        views.push(@json.parse(wire))
      }
      let (source_schemas, source_capabilities) = @row_host.row_declaration_evidence_members(
        original,
      )
      for wire in source_schemas {
        schemas.push(@json.parse(wire))
      }
      for wire in source_capabilities {
        let capability = @json.parse(wire)
        guard capability is Object(fields) else { return None }
        if fields.get("source_ref") is Some(String(source_ref)) {
          for cid in file_capabilities(source, source_ref) {
            guard fields.get("capability_contract_cids") is Some(Array(values)) else {
              return None
            }
            values.push(Json::string(cid))
            values.sort_by((a, b) => {
              match (a, b) {
                (String(a), String(b)) => a.compare(b)
                _ => 0
              }
            })
          }
        }
        capabilities.push(capability)
      }
      entries.push(@json.parse(original.manifest_entry))
      for mapping in write_bodies(source) {
        mappings.push(@json.parse(mapping))
      }
    }
    for
      (key, values) in [
        ("connector_catalogs", catalogs),
        ("contract_registry", contracts),
        ("source_views", views),
        ("schema_snapshots", schemas),
        ("connector_capabilities", capabilities),
        ("mapping_contracts", mappings),
        ("command_contracts", commands),
      ] {
      guard client_project_mock_members(values) is Ok(coalesced) else {
        return None
      }
      body[key] = coalesced
    }
    guard client_project_mock_members(entries) is Ok(coalesced) else {
      return None
    }
    manifest["connectors"] = coalesced
    body["connector_manifest"] = Json::object(manifest)
    ignore(body.remove("evidence_bundle_cid"))
    guard client_project_mock_wire(Json::object(body)) is Ok(preimage) else {
      return None
    }
    let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
    body["evidence_bundle_cid"] = Json::string(cid)
    guard client_project_mock_wire(Json::object(body)) is Ok(wire) else {
      return None
    }
    Some((wire, cid))
  } catch {
    _ => None
  }
}

///|
/// Project the authored read names onto the same declared views. The caller
/// supplies the current audience decision; the publication Owner admits the
/// resulting alias shape, input contract and environment correspondence.
pub fn client_project_mock_read_aliases(
  original : Json,
  declaration : @row_host.RowDeclaration,
  visible : (String) -> Bool,
) -> Array[Json]? {
  guard original is Object(object) &&
    object.get("query_aliases") is Some(Array(entries)) else {
    return None
  }
  let result = Array(capacity=entries.length())
  for entry in entries {
    guard entry is Object(fields) &&
      fields.get("resource") is Some(String(resource)) else {
      return None
    }
    let mut selected = None
    // Preserve the original declaration's last matching view selection.
    for view in declaration.views {
      if view.resource == resource {
        selected = Some(view)
      }
    }
    guard selected is Some(view) else { return None }
    if !visible(view.resource) {
      continue
    }
    let projected : Map[String, Json] = Map([
      ("sourceRef", Json::string(view.source_ref)),
      ("sourceViewContractCid", Json::string(view.view_cid)),
      ("schemaContractCid", Json::string(view.carrier_schema_cid)),
    ])
    for key, value in fields {
      match key {
        "resource" => ()
        "name" | "request" => projected[key] = value
        _ => projected["public_input_field:" + key] = value
      }
    }
    result.push(Json::object(projected))
  }
  Some(result)
}
