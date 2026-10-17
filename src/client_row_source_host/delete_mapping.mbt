///|
/// A bounded metadata projection of the original declared Relation. This
/// creates existing Mapping DATA only: the provider must independently own its
/// record-id meaning, observation, permissions, current checks and cleanup.
/// No proposed value or writable field is introduced for DELETE.
pub fn prepare_row_delete_mapping(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  permission : String,
  approval : String,
  limits : RowDeclarationLimits,
) -> Result[RowMapping, RowMappingIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_views <= 0 {
    return Err(InvalidSpecification)
  }
  if primary_identity.is_empty() ||
    permission.is_empty() ||
    (approval != "none" && approval != "required") ||
    declaration.views.length() > limits.max_views {
    return Err(InvalidSpecification)
  }
  let (resource_kind, schema) = match
    mapping_original_relation(declaration, resource, primary_identity, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(OutputLimit)
  }
  let schema_wire = try {
    @contract.emit_checked(schema, writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(OutputLimit)
    }
  }
  let target_schema = @json.parse(schema_wire) catch {
    _ => return Err(InvalidSpecification)
  }
  try {
    let request_cid = canonical_cid(
      object([
        ("resource", resource.to_json()),
        ("kind", "delete".to_json()),
        ("key", Json::null()),
        ("target_schema", target_schema),
        ("write_fields", Json::array([])),
        ("row_mapping", object([])),
      ]),
      limits,
    )
    let mapping_ref = "mapping:" +
      declaration.connector_id +
      "/" +
      resource +
      "/delete-" +
      request_cid[7:23].to_owned() +
      ".v1"
    let identity = canonical_cid(
      object([
        ("version", "actql.resource_identity/0.1".to_json()),
        ("provider_namespace", declaration.connector_registration.to_json()),
        ("resource_kind", resource_kind.to_json()),
        ("provider_id_field", primary_identity.to_json()),
        ("output_field", primary_identity.to_json()),
        ("boundary_topology", "connector_connection".to_json()),
      ]),
      limits,
    )
    let (mapping, mapping_cid) = seal(
      [
        ("schema", "actql.mapping_contract/0.1".to_json()),
        ("version", declaration.connector_version.to_json()),
        ("mapping_ref", mapping_ref.to_json()),
        (
          "target_ref",
          ("connector://" + declaration.connector_id + "/" + resource).to_json(),
        ),
        ("connector_manifest_cid", declaration.manifest_entry_cid.to_json()),
        ("resource_identity_cid", identity.to_json()),
        ("target_schema", target_schema),
        (
          "target_schema_identity",
          canonical_cid(target_schema, limits).to_json(),
        ),
        ("primary_identity", primary_identity.to_json()),
        ("writable_fields", Json::array([])),
        ("required_fields", Json::array([])),
        ("conversions", Json::array([])),
        (
          "permission_rules",
          Json::array([
            object([
              ("effect_kind", "delete".to_json()),
              ("selector_class", "id".to_json()),
              ("write_fields", Json::array([])),
              ("permissions", Json::array([permission.to_json()])),
            ]),
          ]),
        ),
        ("required_permissions", Json::array([])),
        ("minimum_approval", approval.to_json()),
        ("row_mapping", object([])),
      ],
      "mapping_contract_cid",
      limits,
    )
    Ok({
      resource,
      mapping_ref,
      mapping_cid,
      body: canonical_text(mapping, limits),
      write_fields: [],
      omittable: [],
    })
  } catch {
    _ => Err(OutputLimit)
  }
}
