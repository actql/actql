///|
/// Limits shared by every environment that exports a completed Relation for
/// formal publication. Keeping the complete limit set portable prevents an
/// adapter from silently weakening identity or schema admission.
pub(all) struct PublicationOutputExportLimits {
  max_result_fields : Int
  max_result_mapping_work : Int
  max_result_order_work : Int
  max_result_workspace_entries : Int
  max_rows : Int
  values : @execution.ValueLimits
  payload_wire : @execution.RowWireLimits
  logical_wire : @execution.RowWireLimits
  schema : @execution.RelationSchemaIdentityLimits
  max_batch_bytes : Int
}

///|
/// Portable failures for the completed-output publication boundary.
pub(all) enum PublicationOutputExportIssue {
  InvalidState
  UnknownResult
  Output(@execution.CompletedExportIssue)
  Evidence(@publication.ResultEvidenceIssuanceIssue)
  Artifact(@publication.ResultArtifactIssuanceIssue)
  Capture(@publication.CapturedRunIssuanceIssue)
}

///|
/// Opaque state for one bounded export. Environment adapters may persist the
/// emitted chunks, but all value interpretation and evidence issuance stays
/// in this portable owner.
struct PublicationOutputExport {
  stream : @execution.CompletedOutputExport
  replay_values : @execution.ValueLimits
  replay_wire : @execution.RowWireLimits
  max_batch_bytes : Int
  definition : @publication.PublicationContract?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut evidence : @publication.ResultOrderingEvidence?
  mut artifact : @publication.PublicationContract?
}

///|
/// Bounded second traversal of the already identified immutable Result view.
/// It exists so a Store can receive bytes only after the exact semantic and
/// publication bindings are known.
struct PublicationOutputReplay {
  stream : @execution.CompletedOutputExport
  expected : (String, Int, Int, Int)
  mut finished : Bool
}

///|
pub fn prepare_publication_output_export(
  output : @execution.CompletedOutput,
  limits : PublicationOutputExportLimits,
) -> Result[PublicationOutputExport, PublicationOutputExportIssue] {
  @execution.prepare_completed_relation_export(
    output,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  )
  .map(stream => {
    stream,
    replay_values: limits.values,
    replay_wire: limits.payload_wire,
    max_batch_bytes: limits.max_batch_bytes,
    definition: None,
    receipt: None,
    evidence: None,
    artifact: None,
  })
  .map_err(issue => Output(issue))
}

///|
/// Prepare the exact checked Named Result occurrence from a captured Run.
/// Result lookup, projection, and ordering are fixed before any bytes escape.
pub fn prepare_captured_result_publication_export(
  run : @strategy.CapturedDAG,
  result : Int,
  limits : PublicationOutputExportLimits,
) -> Result[PublicationOutputExport, PublicationOutputExportIssue] {
  let graph = @strategy.captured_dag_graph(run)
  guard @strategy.graph_result_task(graph, result) is Some(task) else {
    return Err(UnknownResult)
  }
  guard @strategy.graph_result_occurrence(graph, result) is Some(occurrence) else {
    return Err(UnknownResult)
  }
  guard @strategy.graph_result_name(graph, result) is Some(result_name) else {
    return Err(UnknownResult)
  }
  let definition = match
    @publication.prepare_result_definition(
      @strategy.graph_program_definition_cid(graph),
      result_name,
    ) {
    Ok(value) => @publication.result_definition_contract(value)
    Err(_) => return Err(UnknownResult)
  }
  guard @strategy.captured_task_target(run, task) is Some(target) else {
    return Err(UnknownResult)
  }
  guard @strategy.captured_task_output(run, task, target) is Some(output) else {
    return Err(UnknownResult)
  }
  @execution.prepare_completed_result_relation_export(
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
  .map(stream => {
    stream,
    replay_values: limits.values,
    replay_wire: limits.payload_wire,
    max_batch_bytes: limits.max_batch_bytes,
    definition: Some(definition),
    receipt: None,
    evidence: None,
    artifact: None,
  })
  .map_err(issue => Output(issue))
}

///|
/// Re-open the exact identified Result view for bounded durable persistence.
/// The replay is accepted only if its final physical receipt matches the first
/// traversal, while logical identity remains owned by that first traversal.
pub fn PublicationOutputExport::replay(
  self : PublicationOutputExport,
) -> Result[PublicationOutputReplay, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  let expected = @execution.output_stream_identity(
    @execution.completed_relation_export_content(receipt),
  )
  @execution.replay_completed_relation_export(
    self.stream,
    receipt,
    self.replay_values,
    self.replay_wire,
    self.max_batch_bytes,
  )
  .map(stream => { stream, expected, finished: false, })
  .map_err(issue => Output(issue))
}

///|
pub fn PublicationOutputReplay::next(
  self : PublicationOutputReplay,
) -> Result[String?, PublicationOutputExportIssue] {
  if self.finished {
    return Err(InvalidState)
  }
  @execution.next_completed_output_export(self.stream).map_err(issue => {
    Output(issue)
  })
}

///|
pub fn PublicationOutputReplay::finish(
  self : PublicationOutputReplay,
) -> Result[String, PublicationOutputExportIssue] {
  if self.finished {
    return Err(InvalidState)
  }
  match @execution.finish_completed_output_export(self.stream) {
    Ok((receipt, tail)) => {
      self.finished = true
      let actual = @execution.output_stream_identity(
        @execution.completed_export_content(receipt),
      )
      @execution.cancel_completed_export_receipt(receipt)
      if actual == self.expected {
        Ok(tail)
      } else {
        Err(Output(@execution.ForeignMaterial))
      }
    }
    Err(issue) => Err(Output(issue))
  }
}

///|
pub fn PublicationOutputReplay::cancel(self : PublicationOutputReplay) -> Unit {
  if !self.finished {
    @execution.cancel_completed_output_export(self.stream)
    self.finished = true
  }
}

///|
pub fn PublicationOutputExport::next(
  self : PublicationOutputExport,
) -> Result[String?, PublicationOutputExportIssue] {
  if self.receipt is Some(_) {
    return Err(InvalidState)
  }
  @execution.next_completed_output_export(self.stream).map_err(issue => {
    Output(issue)
  })
}

///|
/// Finish the canonical traversal. The returned tail must still be accepted
/// by durable storage before the receipt can be bound to a representation.
pub fn PublicationOutputExport::finish(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  if self.receipt is Some(_) {
    return Err(InvalidState)
  }
  match @execution.finish_completed_relation_export(self.stream) {
    Ok((receipt, tail)) => {
      self.receipt = Some(receipt)
      Ok(tail)
    }
    Err(issue) => Err(Output(issue))
  }
}

///|
fn PublicationOutputExport::content_identity(
  self : PublicationOutputExport,
) -> Result[(String, Int, Int, Int), PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ),
  )
}

///|
pub fn PublicationOutputExport::content_cid(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  self.content_identity().map(value => value.0)
}

///|
pub fn PublicationOutputExport::content_bytes(
  self : PublicationOutputExport,
) -> Result[Int, PublicationOutputExportIssue] {
  self.content_identity().map(value => value.1)
}

///|
pub fn PublicationOutputExport::content_nodes(
  self : PublicationOutputExport,
) -> Result[Int, PublicationOutputExportIssue] {
  self.content_identity().map(value => value.2)
}

///|
pub fn PublicationOutputExport::row_count(
  self : PublicationOutputExport,
) -> Result[Int, PublicationOutputExportIssue] {
  self.content_identity().map(value => value.3)
}

///|
pub fn PublicationOutputExport::logical_relation_cid(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ),
  )
}

///|
pub fn PublicationOutputExport::result_schema_cid(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
  )
}

///|
pub fn PublicationOutputExport::result_schema_wire(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(
    @execution.relation_schema_wire(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
  )
}

///|
pub fn PublicationOutputExport::result_fields(
  self : PublicationOutputExport,
) -> Result[Array[String], PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(@execution.completed_relation_export_field_names(receipt))
}

///|
pub fn PublicationOutputExport::codec_contract_cid(
  self : PublicationOutputExport,
) -> Result[String, PublicationOutputExportIssue] {
  guard self.receipt is Some(_) else { return Err(InvalidState) }
  Ok(@execution.ordered_rows_canonical_contract_cid())
}

///|
pub fn PublicationOutputExport::schema_usage(
  self : PublicationOutputExport,
) -> Result[(Int, Int, Int), PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  Ok(
    @execution.relation_schema_usage(
      @execution.completed_relation_export_schema_identity(receipt),
    ),
  )
}

///|
pub fn PublicationOutputExport::issue_result_evidence(
  self : PublicationOutputExport,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  guard self.definition is Some(definition) else { return Err(InvalidState) }
  if self.evidence is Some(_) {
    return Err(InvalidState)
  }
  match
    @publication.issue_result_occurrence_evidence(
      definition,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
      computation_contract_cid,
      input_relation_cids,
      scope_cid,
      effective_data_policy_cid,
      "actql-common-host",
      authority_scope_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(evidence) => {
      self.evidence = Some(evidence)
      Ok(())
    }
    Err(issue) => Err(Evidence(issue))
  }
}

///|
pub fn PublicationOutputExport::definition(
  self : PublicationOutputExport,
) -> Result[@publication.PublicationContract, PublicationOutputExportIssue] {
  guard self.definition is Some(value) else { return Err(InvalidState) }
  Ok(value)
}

///|
pub fn PublicationOutputExport::derivation(
  self : PublicationOutputExport,
) -> Result[@publication.PublicationContract, PublicationOutputExportIssue] {
  guard self.receipt is Some(_) && self.evidence is Some(evidence) else {
    return Err(InvalidState)
  }
  Ok(@publication.result_ordering_derivation_contract(evidence))
}

///|
pub fn PublicationOutputExport::ordering(
  self : PublicationOutputExport,
) -> Result[@publication.PublicationContract, PublicationOutputExportIssue] {
  guard self.receipt is Some(_) && self.evidence is Some(evidence) else {
    return Err(InvalidState)
  }
  Ok(@publication.result_ordering_evidence_contract(evidence))
}

///|
pub fn PublicationOutputExport::issue_artifact(
  self : PublicationOutputExport,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  guard self.definition is Some(definition) else { return Err(InvalidState) }
  guard self.evidence is Some(evidence) else { return Err(InvalidState) }
  if self.artifact is Some(_) {
    return Err(InvalidState)
  }
  let rows = @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).3
  match
    @publication.issue_complete_result_artifact(
      definition, invocation, evidence, retention, rows, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(artifact) => {
      self.artifact = Some(artifact)
      Ok(artifact)
    }
    Err(issue) => Err(Artifact(issue))
  }
}

///|
pub fn PublicationOutputExport::admit_captured_snapshot(
  self : PublicationOutputExport,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.CapturedResultSnapshot, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) else { return Err(InvalidState) }
  guard self.definition is Some(definition) else { return Err(InvalidState) }
  guard self.artifact is Some(artifact) else { return Err(InvalidState) }
  let (rows_wire, fields) = match
    @execution.completed_relation_export_snapshot(
      self.stream,
      receipt,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  @publication.admit_captured_result_snapshot(
    definition, artifact, rows_wire, fields, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Capture(issue))
}

///|
pub fn PublicationOutputExport::cancel(self : PublicationOutputExport) -> Unit {
  match self.receipt {
    Some(receipt) => {
      @execution.cancel_completed_relation_export_receipt(receipt)
      self.receipt = None
      self.evidence = None
      self.artifact = None
    }
    None => @execution.cancel_completed_output_export(self.stream)
  }
}
