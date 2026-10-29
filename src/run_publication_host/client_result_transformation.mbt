///|
/// One checked Result occurrence, including its projection and publication
/// order. This is a logical selection, not a physical task or a Run claim.
pub struct ClientResultTransformation {
  owner : PreparedClientProgram
  result : Int
  occurrence : @execution.ManagedResultOccurrence
  plan : ClientResultPlanIdentity
  definition : @publication.PublicationContract
  priv plan_limits : (Int, Int, Int)
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
  Ok({
    owner,
    result,
    occurrence,
    plan,
    definition,
    plan_limits: (max_wire_bytes, max_nodes, max_depth),
  })
}

///|
/// Resolve the Result from the original compiler-retained checked Program.
/// Composed Model children need no standalone pure Program handle; the same
/// Run/Invocation binding still has to retain and authorize their completion.
pub fn prepare_client_compiled_result_transformation(
  compiled : ClientCompiledRun,
  result : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultTransformation, ClientResultTransformationIssue] {
  prepare_client_result_transformation(
    compiled.owner,
    result,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn client_result_transformation_plan(
  value : ClientResultTransformation,
) -> ClientResultPlanIdentity {
  value.plan
}

///|
/// Publication inventory readers preserve the actual checked Result selection.
/// A caller-supplied name or task number cannot replace this occurrence.
pub fn client_result_transformation_name(
  value : ClientResultTransformation,
) -> String {
  @execution.managed_result_occurrence_name(value.occurrence)
}

///|
pub fn client_result_transformation_task(
  value : ClientResultTransformation,
) -> Int {
  @strategy.graph_result_task(value.owner.graph, value.result).unwrap()
}

///|
pub fn client_result_transformation_definition(
  value : ClientResultTransformation,
) -> @publication.PublicationContract {
  value.definition
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
  occurrence : @execution.ManagedResultOccurrence
  definition : @publication.PublicationContract
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
  start_result_publication_export(
    output,
    selection.occurrence,
    selection.definition,
    limits,
  )
}

///|
/// The same Result view owner can prepare an exact captured occurrence without
/// an additional Client selection. The occurrence still supplies the checked
/// projection and total publication order; this is not an unselected row dump.
pub fn start_result_publication_export(
  output : @execution.CompletedOutput,
  occurrence : @execution.ManagedResultOccurrence,
  definition : @publication.PublicationContract,
  limits : PublicationOutputExportLimits,
) -> Result[
  ClientResultTransformationPreparation,
  ClientResultTransformationIssue,
] {
  @execution.start_completed_result_relation_export(
    output,
    occurrence,
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
  .map(preparation => { occurrence, definition, preparation, limits, })
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
/// A transport must charge the existing view's observed progress before
/// interpreting a failed poll. No new Result view or accounting owner is made.
pub fn ClientResultTransformationPreparation::advance_progress(
  self : ClientResultTransformationPreparation,
  quantum : Int,
) -> (Bool, Int, ClientResultTransformationIssue?) {
  let (ready, work, issue) = @execution.advance_completed_result_relation_export_progress(
    self.preparation,
    quantum,
  )
  (ready, work, issue.map(issue => Output(issue)))
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
    max_snapshot_workspace: self.limits.max_result_workspace_entries,
    definition: Some(self.definition),
    declared_fields: Some(
      @results.fields(
        @results.port_result(
          @execution.managed_result_occurrence_port(self.occurrence),
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
