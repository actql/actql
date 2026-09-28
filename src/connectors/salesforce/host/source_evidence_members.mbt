///|
/// The Check Environment source evidence members of one generated
/// declaration, as canonical texts: for each declared view, the schema
/// snapshot its publication observed and this implementation's capability
/// (the broad-receipt process-evidence contract). The declaration's data
/// policies classify every view as `unknown`.
pub fn salesforce_source_evidence_members(
  declaration : @catalog.StaticDeclaration,
) -> (Array[String], Array[String]) raise @encode.EncodeFailure {
  let schemas = []
  let capabilities = []
  for view in declaration.views {
    if view.carrier_schema_cid.is_empty() || view.data_policy_cid.is_empty() {
      raise @encode.EncodeFailure::InvalidStructure
    }
    let schema = @encode.writer(4096, 64, 8)
    @encode.begin_object(schema)
    for
      (key, value) in [
        ("carrier_schema_contract_cid", view.carrier_schema_cid),
        ("data_classification", "unknown"),
        ("output_carrier", "relation"),
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_data_policy_cid", view.data_policy_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(schema, key)
      @encode.string_value(schema, value)
    }
    @encode.end_object(schema)
    schemas.push(@encode.finish(schema))
    let capability = @encode.writer(4096, 64, 8)
    @encode.begin_object(capability)
    @encode.key(capability, "capability_contract_cids")
    @encode.begin_array(capability)
    @encode.string_value(
      capability,
      @planning.query_evidence_contract_identity(),
    )
    @encode.end_array(capability)
    for
      (key, value) in [
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(capability, key)
      @encode.string_value(capability, value)
    }
    @encode.end_object(capability)
    capabilities.push(@encode.finish(capability))
  }
  (schemas, capabilities)
}
