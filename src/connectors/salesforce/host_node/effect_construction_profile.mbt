///|
/// Closed installing-code arguments. The returned original Option and tuples
/// go unchanged to Core's existing described-record recipe composer.
#export_name("salesforceEffectConstructionProfile")
pub fn salesforce_effect_construction_profile(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  path_bytes : Int,
  target_bytes : Int,
  request_bytes : Int,
  target_response_bytes : Int,
  target_nodes : Int,
  target_depth : Int,
  identity_bytes : Int,
  response_bytes : Int,
  response_nodes : Int,
  response_depth : Int,
  describe_bytes : Int,
  describe_nodes : Int,
  describe_depth : Int,
  describe_fields : Int,
  describe_names : Int,
  observation_bytes : Int,
  binding_units : Int,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  @salesforce_host.effect_construction_profile(
    { max_bytes: body_bytes, max_nodes: body_nodes, max_depth: body_depth, },
    {
      max_path_bytes: path_bytes,
      max_target_bytes: target_bytes,
      max_body_bytes: request_bytes,
    },
    {
      max_bytes: target_response_bytes,
      max_nodes: target_nodes,
      max_depth: target_depth,
      max_identity_bytes: identity_bytes,
    },
    {
      max_bytes: response_bytes,
      max_nodes: response_nodes,
      max_depth: response_depth,
      max_rows: 1,
    },
    {
      max_bytes: describe_bytes,
      max_nodes: describe_nodes,
      max_depth: describe_depth,
      max_fields: describe_fields,
      max_name_units: describe_names,
    },
    observation_bytes,
    binding_units,
    fields,
    field_name_units,
    api_units,
    resource_units,
  )
}

///|
#export_name("salesforceEffectCaptureConstructionProfile")
pub fn salesforce_effect_capture_construction_profile(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  list_bytes : Int,
  list_nodes : Int,
  list_depth : Int,
  list_resources : Int,
  list_selected : Int,
  list_names : Int,
  describe_bytes : Int,
  describe_nodes : Int,
  describe_depth : Int,
  describe_fields : Int,
  describe_names : Int,
  observation_bytes : Int,
  raw_bytes : Int,
  recovery_bytes : Int,
  binding_units : Int,
  fields : Int,
  field_name_units : Int,
  api_units : Int,
  resource_units : Int,
) -> Array[@execution.ExecutionCapacity]? {
  @salesforce_host.effect_capture_construction_profile(
    original,
    {
      max_input_bytes: preview_bytes,
      max_nodes: preview_nodes,
      max_depth: preview_depth,
    },
    {
      max_bytes: list_bytes,
      max_nodes: list_nodes,
      max_depth: list_depth,
      max_resources: list_resources,
      max_selected: list_selected,
      max_name_units: list_names,
    },
    {
      max_bytes: describe_bytes,
      max_nodes: describe_nodes,
      max_depth: describe_depth,
      max_fields: describe_fields,
      max_name_units: describe_names,
    },
    observation_bytes,
    raw_bytes,
    recovery_bytes,
    binding_units,
    fields,
    field_name_units,
    api_units,
    resource_units,
  )
}
