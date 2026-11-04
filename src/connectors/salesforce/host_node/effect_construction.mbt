///|
#export_name("salesforceEffectDriverConstructionCapacity")
pub fn salesforce_effect_driver_construction_capacity() -> @execution.ExecutionCapacity? {
  @salesforce_host.effect_driver_construction_capacity()
}

///|
#export_name("salesforceEffectRecoveryPreviewConstructionCapacity")
pub fn salesforce_effect_recovery_preview_construction_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.effect_recovery_preview_construction_capacity(
    bytes, nodes, depth,
  )
}

///|
/// Reuse the existing Salesforce named Describe Owner's complete constructor
/// geometry. These immutable quantities do not perform a provider read or
/// admit an Effect; the same checked Plan adds physical/secret/Host overlap.
#export_name("salesforceEffectMetadataConstructionCapacity")
pub fn salesforce_effect_metadata_construction_capacity(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_units : Int,
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.named_describe_construction_capacity(
    { max_bytes, max_nodes, max_depth, max_fields, max_name_units, },
    max_observation_bytes,
    binding_units,
    resource_units,
  )
}

///|
/// Original request/body constructor quantities only. The caller supplies
/// immutable implementation limits and actual original declaration lengths;
/// the same managed Plan still owns admission, authority and retirement.
#export_name("salesforceEffectRequestConstructionCapacity")
pub fn salesforce_effect_request_construction_capacity(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  path_bytes : Int,
  target_bytes : Int,
  request_bytes : Int,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.effect_request_construction_capacity(
    { max_bytes: body_bytes, max_nodes: body_nodes, max_depth: body_depth, },
    {
      max_path_bytes: path_bytes,
      max_target_bytes: target_bytes,
      max_body_bytes: request_bytes,
    },
    fields,
    field_name_units,
    api_units,
    resource_units,
  )
}

///|
#export_name("salesforceEffectTargetConstructionCapacity")
pub fn salesforce_effect_target_construction_capacity(
  response_bytes : Int,
  response_nodes : Int,
  response_depth : Int,
  identity_bytes : Int,
  fields : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.effect_target_construction_capacity(
    {
      max_bytes: response_bytes,
      max_nodes: response_nodes,
      max_depth: response_depth,
      max_identity_bytes: identity_bytes,
    },
    fields,
  )
}

///|
#export_name("salesforceEffectResponseConstructionCapacity")
pub fn salesforce_effect_response_construction_capacity(
  response_bytes : Int,
  response_nodes : Int,
  response_depth : Int,
  identity_bytes : Int,
  fields : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.effect_response_construction_capacity(
    {
      max_bytes: response_bytes,
      max_nodes: response_nodes,
      max_depth: response_depth,
      max_rows: 1,
    },
    identity_bytes,
    fields,
  )
}
