///|
/// Original Model input/output custody remains with the invocation binding.
/// This is a typed borrowed outcome relation, not a Result or Source grant.
#export_name("clientProgramInferInvocationBindingOriginalModelOutcomes")
pub fn client_program_infer_invocation_binding_original_model_outcomes(
  binding : @infer_host.InvocationBinding,
) -> @execution.CompletedOutput? {
  @infer_host.invocation_binding_original_model_outcomes(binding)
}

///|
#export_name("clientProgramIssueInferInvocationBindingOriginalModelObservation")
pub fn client_program_issue_infer_invocation_binding_original_model_observation(
  binding : @infer_host.InvocationBinding,
  receipt : @execution.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @infer_host.LocalModelObservation? {
  @infer_host.issue_invocation_binding_original_model_observation(
    binding, receipt, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramOriginalModelObservationBody")
pub fn client_program_original_model_observation_body(
  value : @infer_host.LocalModelObservation,
) -> (String, String)? {
  @infer_host.original_local_model_observation_body(value).map(body => {
    (
      @publication.captured_effect_dependency_body_cid(body),
      @publication.captured_effect_dependency_body_json(body),
    )
  })
}

///|
#export_name("clientProgramOriginalModelObservationCoordinates")
pub fn client_program_original_model_observation_coordinates(
  value : @infer_host.LocalModelObservation,
) -> (Int, Int, Int)? {
  @infer_host.original_local_model_observation_coordinates(value)
}

///|
#export_name("clientProgramOriginalModelAcquiredEffectEvidence")
pub fn client_program_original_model_acquired_effect_evidence(
  value : @infer_host.LocalModelObservation,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports : @publication_host.ClientEffectImportedEvidence?,
) -> Result[
  @publication_host.ClientEffectModelAcquiredEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @infer_host.issue_original_local_model_acquired_evidence(
    value,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
    imports~,
  )
}

///|
/// Technical DATA from the SAME returned failure, without observing current,
/// replaying validation or decoding the compiler representation in JavaScript.
#export_name("clientProgramOriginalModelAcquiredEffectEvidenceIssueKind")
pub fn client_program_original_model_acquired_effect_evidence_issue_kind(
  result : Result[
    @publication_host.ClientEffectModelAcquiredEvidence,
    @publication_host.ClientEffectAcquiredEvidenceIssue,
  ],
) -> String? {
  match result {
    Ok(_) => None
    Err(Invocation(issue)) =>
      Some(
        match issue {
          MissingUnit => "invocation.missing_unit"
          NotSourceFree => "invocation.not_source_free"
          ForeignCapturedInput => "invocation.foreign_captured_input"
          MissingCapturedInput => "invocation.missing_captured_input"
          ForeignSourceObservation => "invocation.foreign_source_observation"
          IncompleteResultImports => "invocation.incomplete_result_imports"
          ForeignResultImport => "invocation.foreign_result_import"
          Encoding => "invocation.encoding"
        },
      )
    Err(Relation(_)) => Some("relation")
    Err(Dependency(_)) => Some("dependency")
  }
}

///|
#export_name("clientProgramOriginalModelAcquiredEffectInvocation")
pub fn client_program_original_model_acquired_effect_invocation(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> @publication_host.ClientEffectLocalInvocation {
  @publication_host.client_effect_model_acquired_invocation(value)
}

///|
#export_name("clientProgramOriginalModelAcquiredEffectScope")
pub fn client_program_original_model_acquired_effect_scope(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> String {
  @publication_host.client_effect_model_acquired_scope_json(value)
}

///|
#export_name("clientProgramOriginalModelAcquiredEffectSources")
pub fn client_program_original_model_acquired_effect_sources(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> Array[@publication_host.ClientEffectAcquiredEvidence] {
  @publication_host.client_effect_model_acquired_direct_sources(value)
}

///|
#export_name("clientProgramOriginalModelAcquiredEffectLookupBarrier")
pub fn client_program_original_model_acquired_effect_lookup_barrier(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> (String, String)? {
  @publication_host.client_effect_model_acquired_lookup_barrier(value)
}

///|
#export_name("clientProgramOriginalModelEffectResultArtifact")
pub fn client_program_original_model_effect_result_artifact(
  value : @infer_host.LocalModelObservation,
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @publication_host.ClientEffectModelAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @infer_host.issue_original_local_model_effect_artifact_with_context(
    value, owner, inputs, exported, acquired, definition, receipt, admission, run_definition,
    invocation, observation, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramInferModelIdentityStartCapacity")
pub fn client_program_infer_model_identity_start_capacity(
  binding : @infer_host.InvocationBinding,
) -> (Int64, Int64)? {
  @infer_host.invocation_binding_original_model_identity_start_capacity(binding).map(capacity => {
      (
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
      )
    },
  )
}

///|
#export_name("clientProgramInferModelIdentityStart")
pub fn client_program_infer_model_identity_start(
  binding : @infer_host.InvocationBinding,
) -> Result[
  @execution.CompletedRelationIdentityScan,
  @execution.CompletedExportIssue,
] {
  @infer_host.start_invocation_binding_original_model_identity(binding)
}

///|
#export_name("clientProgramInferModelIdentityNextCapacity")
pub fn client_program_infer_model_identity_next_capacity(
  scan : @execution.CompletedRelationIdentityScan,
) -> (Int64, Int64)? {
  @execution.completed_relation_identity_scan_next_construction_capacity(scan).map(capacity => {
      (
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
      )
    },
  )
}

///|
#export_name("clientProgramInferModelIdentityAdvance")
pub fn client_program_infer_model_identity_advance(
  scan : @execution.CompletedRelationIdentityScan,
  quantum : Int,
  retained : Int64,
  execution : Int64,
) -> Result[(Bool, Int), @execution.CompletedExportIssue] {
  guard @execution.execution_capacity(retained, execution) is Some(capacity) else {
    return Err(Admission(InvalidCaptureLimits))
  }
  @execution.advance_completed_relation_identity_scan(
    scan,
    quantum,
    construction_capacity=Some(capacity),
  )
}

///|
#export_name("clientProgramInferModelObservationCapacity")
pub fn client_program_infer_model_observation_capacity(
  binding : @infer_host.InvocationBinding,
  receipt : @execution.CompletedRelationExportReceipt,
  max_bytes : Int,
) -> (Int64, Int64)? {
  @infer_host.invocation_binding_original_model_observation_capacity(
    binding, receipt, max_bytes,
  ).map(capacity => {
    (
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    )
  })
}

///|
#export_name("clientProgramOriginalModelObservationInputBodies")
pub fn client_program_original_model_observation_input_bodies(
  value : @infer_host.LocalModelObservation,
) -> Array[(String, String, String)]? {
  @infer_host.original_local_model_observation_input_dependency_bodies(value)
}

///|
#export_name("clientProgramInferModelIdentityBody")
pub fn client_program_infer_model_identity_body(
  scan : @execution.CompletedRelationIdentityScan,
  receipt : @execution.CompletedRelationExportReceipt,
) -> String? {
  @execution.completed_relation_identity_scan_body(scan, receipt)
}

///|
#export_name("clientProgramInferModelIdentityFinish")
pub fn client_program_infer_model_identity_finish(
  scan : @execution.CompletedRelationIdentityScan,
) -> Result[
  @execution.CompletedRelationExportReceipt,
  @execution.CompletedExportIssue,
] {
  @execution.finish_completed_relation_identity_scan(scan)
}

///|
#export_name("clientProgramInferModelIdentityCancel")
pub fn client_program_infer_model_identity_cancel(
  scan : @execution.CompletedRelationIdentityScan,
) -> Bool {
  @execution.cancel_completed_relation_identity_scan(scan)
}

///|
#export_name("clientProgramInferModelIdentityReceiptCancel")
pub fn client_program_infer_model_identity_receipt_cancel(
  receipt : @execution.CompletedRelationExportReceipt,
) -> Unit {
  @execution.cancel_completed_relation_export_receipt(receipt)
}
