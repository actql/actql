///|
/// One checked Result occurrence, including its projection and publication
/// order. This is a logical selection, not a physical task or a Run claim.
pub struct ClientResultTransformation {
  owner : PreparedClientProgram
  result : Int
  occurrence : @execution.ManagedResultOccurrence
  plan : ClientResultPlanIdentity
  definition : @publication.PublicationContract
}

///|
pub(all) enum ClientResultTransformationIssue {
  MissingResult
  Plan(ClientResultPlanIssue)
  Definition(@publication.ResultDefinitionIssue)
  Output(@execution.CompletedExportIssue)
}

///|
/// Select through the checked Program, never through a caller-authored schema,
/// order, Result name, or publication Definition.
pub fn prepare_client_result_transformation(
  owner : PreparedClientProgram,
  result : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultTransformation, ClientResultTransformationIssue] {
  guard @strategy.graph_result_occurrence(owner.graph, result)
    is Some(occurrence) else {
    return Err(MissingResult)
  }
  let plan = match
    issue_prepared_client_result_plan(
      owner, result, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let definition = match
    @publication.prepare_result_definition(
      prepared_client_identity(owner).program_definition_cid,
      client_result_plan_name(plan),
    ) {
    Ok(value) => @publication.result_definition_contract(value)
    Err(issue) => return Err(Definition(issue))
  }
  Ok({ owner, result, occurrence, plan, definition, })
}

///|
pub fn client_result_transformation_plan(
  value : ClientResultTransformation,
) -> ClientResultPlanIdentity {
  value.plan
}

///|
pub fn client_result_transformation_matches(
  value : ClientResultTransformation,
  owner : PreparedClientProgram,
  result : Int,
) -> Bool {
  physical_equal(value.owner, owner) && value.result == result
}

///|
/// Resumable use of the existing Result index-view transform. The caller keeps
/// its completed producer/managed bridge live until the returned export closes.
/// This handle grants neither execution authority nor a new retention hold.
pub struct ClientResultTransformationPreparation {
  selection : ClientResultTransformation
  preparation : @execution.CompletedResultRelationExportPreparation
  limits : PublicationOutputExportLimits
}

///|
pub fn start_client_result_transformation(
  selection : ClientResultTransformation,
  output : @execution.CompletedOutput,
  limits : PublicationOutputExportLimits,
) -> Result[
  ClientResultTransformationPreparation,
  ClientResultTransformationIssue,
] {
  @execution.start_completed_result_relation_export(
    output,
    selection.occurrence,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  )
  .map(preparation => { selection, preparation, limits, })
  .map_err(issue => Output(issue))
}

///|
pub fn ClientResultTransformationPreparation::advance(
  self : ClientResultTransformationPreparation,
  quantum : Int,
) -> Result[(Bool, Int), ClientResultTransformationIssue] {
  @execution.advance_completed_result_relation_export(self.preparation, quantum).map_err(issue => {
      Output(issue)
    },
  )
}

///|
/// Only a fully transformed view can enter the existing publication exporter.
/// Its receipt, logical CID, schema and ordering evidence are then derived from
/// that view by PublicationOutputExport, not from the untransformed producer.
pub fn ClientResultTransformationPreparation::finish(
  self : ClientResultTransformationPreparation,
) -> Result[PublicationOutputExport, ClientResultTransformationIssue] {
  @execution.finish_completed_result_relation_export_preparation(
    self.preparation,
  )
  .map(stream => {
    stream,
    retained: None,
    replay_values: self.limits.values,
    replay_wire: self.limits.payload_wire,
    max_batch_bytes: self.limits.max_batch_bytes,
    definition: Some(self.selection.definition),
    declared_fields: Some(
      @results.fields(
        @results.port_result(
          @execution.managed_result_occurrence_port(self.selection.occurrence),
        ),
      ),
    ),
    receipt: None,
    evidence: None,
    artifact: None,
  })
  .map_err(issue => Output(issue))
}

///|
pub fn ClientResultTransformationPreparation::cancel(
  self : ClientResultTransformationPreparation,
) -> Bool {
  @execution.cancel_completed_result_relation_export(self.preparation)
}
