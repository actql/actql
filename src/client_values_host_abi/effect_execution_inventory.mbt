///|
#export_name("clientValuesHostEffectTaskKeys")
pub fn client_values_host_effect_task_keys(
  compilation : @host.ClientEffectCompilation,
) -> Result[Array[String], @host.ClientTaskFragmentIssue] {
  @host.client_effect_compilation_task_keys(compilation)
}

///|
#export_name("clientValuesHostEffectResultNames")
pub fn client_values_host_effect_result_names(
  compilation : @host.ClientEffectCompilation,
) -> Array[String] {
  @host.client_effect_compilation_result_names(compilation)
}

///|
#export_name("clientValuesHostEffectResultDefinitions")
pub fn client_values_host_effect_result_definitions(
  compilation : @host.ClientEffectCompilation,
) -> Result[Array[String], @publication.PublicationInventoryIssue] {
  let inventory = match
    @host.prepare_client_effect_publication_inventory(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields = []
  for index in 0..<@publication.checked_publication_inventory_count(inventory) {
    let name = match
      @publication.checked_publication_inventory_name(inventory, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = match
      @publication.checked_publication_inventory_definition_cid(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let wire = match
      @publication.checked_publication_inventory_definition_json(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    fields.push(name)
    fields.push(cid)
    fields.push(wire)
  }
  Ok(fields)
}

///|
#export_name("clientValuesHostEffectResultSchema")
pub fn client_values_host_effect_result_schema(
  compilation : @host.ClientEffectCompilation,
  result : Int,
) -> Result[Array[String], @host.ClientTaskOutputSchemaIssue] {
  let schema = match
    @host.issue_client_effect_result_schema(compilation, result, {
      max_fields: 100,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let facts = [
    @execution.relation_schema_cid(schema),
    @execution.relation_schema_wire(schema),
  ]
  for field in @execution.relation_schema_field_names(schema) {
    facts.push(field)
  }
  Ok(facts)
}

///|
#export_name("clientValuesHostEffectSourceEvidenceFacts")
pub fn client_values_host_effect_source_evidence_facts(
  compilation : @host.ClientEffectCompilation,
  stage : Int,
  source_index : Int,
) -> Array[String]? {
  @host.client_effect_source_evidence_facts(compilation, stage, source_index).map(
    @planning.query_source_evidence_fact_values,
  )
}
