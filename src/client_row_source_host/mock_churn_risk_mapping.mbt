///|
// This checks the original View's facts reference, not a supplied key label or
// a second SourceView. Physical fixture-key admission remains with its reader.
fn mock_churn_risk_original_key(
  declaration : RowDeclaration,
  limits : RowDeclarationLimits,
  identity : String,
) -> Result[Unit, RowMappingIssue] {
  let (view, _, used_bytes, used_nodes) = match
    mapping_read_original(
      declaration.view_bodies[0],
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard view is Object(view_fields) &&
    view_fields.get("output") is Some(Object(output)) &&
    output.get("facts") is Some(Object(reference)) &&
    reference.get("cid") is Some(String(cid)) else {
    return Err(InvalidSpecification)
  }
  let mut bytes = limits.max_bytes - used_bytes
  let mut nodes = limits.max_nodes - used_nodes
  let mut found = false
  for wire in declaration.contracts {
    let (original, _, used_bytes, used_nodes) = match
      mapping_read_original(wire, bytes, nodes, limits.max_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    bytes -= used_bytes
    nodes -= used_nodes
    guard original is Object(fields) else { return Err(InvalidSpecification) }
    if fields.get("cid") != Some(cid.to_json()) {
      continue
    }
    guard !found &&
      fields.get("kind") == Some("carrier_facts".to_json()) &&
      mapping_original_identity(original, "cid", cid, limits) &&
      fields.get("body") is Some(Object(body)) &&
      body.length() == 1 &&
      body.get("relation_keys") is Some(Object(keys)) &&
      keys.length() == 1 &&
      keys.get("candidate_keys") is Some(Array(candidates)) &&
      candidates.length() == 1 &&
      candidates[0] is Array(key) &&
      key.length() == 1 &&
      key[0] == identity.to_json() else {
      return Err(InvalidSpecification)
    }
    found = true
  }
  if found {
    Ok(())
  } else {
    Err(InvalidSpecification)
  }
}

///|
/// Existing Mapping DATA for the explicitly installed churn-risk mock profile.
/// The actual Host retains this declaration and its installation/target
/// publication. This does not issue a current write grant or a Preview.
pub fn prepare_churn_risk_mock_update_mapping(
  declaration : RowDeclaration,
  limits : RowDeclarationLimits,
) -> Result[RowMapping, RowMappingIssue] {
  if declaration.connector_id != "salesforce" ||
    declaration.connector_registration != "mock_salesforce" ||
    declaration.connector_version != "mock_salesforce/0.1" ||
    declaration.views.length() != 1 ||
    declaration.view_bodies.length() != 1 ||
    declaration.views[0].resource != "Account" {
    return Err(InvalidSpecification)
  }
  let (kind, contract) = match
    mapping_original_relation(declaration, "Account", "id", limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard kind == "record" &&
    @schema.from_object(contract) is Ok(schema) &&
    @schema.field_count(schema) == 5 else {
    return Err(InvalidSpecification)
  }
  for name in ["id", "name", "description", "Churn_Risk__c", "Risk_Reason__c"] {
    guard @schema.lookup_reference(schema, name) is Some(field) else {
      return Err(InvalidSpecification)
    }
    let matches = @contract.type_equal(
      field.contract,
      @contract.primitive(
        @contract.StringType,
        nullable=name == "Risk_Reason__c",
      ),
      limits.max_nodes,
    ) catch {
      _ => false
    }
    if !matches {
      return Err(InvalidSpecification)
    }
  }
  match mock_churn_risk_original_key(declaration, limits, "id") {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  prepare_relation_row_write_mapping(
    declaration,
    "Account",
    "id",
    {
      kind: RelationUpdate,
      writable_fields: ["Churn_Risk__c", "Risk_Reason__c"],
      required_fields: [],
      permission: "salesforce:record:update",
      approval: "required",
    },
    [
      {
        target: "Churn_Risk__c",
        field: "Churn_Risk__c",
        null_behavior: "reject",
      },
      {
        target: "Risk_Reason__c",
        field: "Risk_Reason__c",
        null_behavior: "reject",
      },
    ],
    limits,
  )
}
