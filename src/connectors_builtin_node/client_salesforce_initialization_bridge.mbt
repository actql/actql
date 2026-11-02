///|
#export_name("clientProgramSalesforceInitializationConstructionCapacity")
pub fn client_program_salesforce_initialization_construction_capacity(
  body_lengths : Array[Int],
  encoded_units : Int,
  observation_units : Int,
  name_lengths : Array[Int],
  binding_units : Int,
  connector_units : Int,
  revision_units : Int,
  max_describe_bytes : Int,
  max_describe_nodes : Int,
  max_describe_depth : Int,
  max_describe_fields : Int,
  max_describe_name_units : Int,
  max_observation_bytes : Int,
  max_declaration_bytes : Int,
  max_declaration_nodes : Int,
  max_declaration_depth : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.initialization_construction_capacity(
    body_lengths,
    encoded_units,
    observation_units,
    name_lengths,
    binding_units,
    connector_units,
    revision_units,
    {
      max_bytes: max_describe_bytes,
      max_nodes: max_describe_nodes,
      max_depth: max_describe_depth,
      max_fields: max_describe_fields,
      max_name_units: max_describe_name_units,
    },
    max_observation_bytes,
    {
      max_bytes: max_declaration_bytes,
      max_nodes: max_declaration_nodes,
      max_depth: max_declaration_depth,
    },
  )
}

///|
#export_name("clientProgramSalesforceExecutionMappingConstructionCapacity")
pub fn client_program_salesforce_execution_mapping_construction_capacity(
  field_count : Int,
  field_units : Int,
  source_count : Int,
  source_units : Int,
  key_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  describe_bytes : Int,
  max_fields : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  @salesforce_host.execution_mapping_construction_capacity(
    field_count,
    field_units,
    source_count,
    source_units,
    key_units,
    resource_units,
    connector_units,
    revision_units,
    describe_bytes,
    max_fields,
    { max_bytes, max_nodes, max_depth, },
  )
}
