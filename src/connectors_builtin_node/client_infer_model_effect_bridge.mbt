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
  source_originals : Array[@publication_host.ClientEffectAcquiredEvidence],
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
    source_originals~,
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
    Err(Relation(issue)) =>
      Some(
        match issue {
          WrongEvidence => "relation.wrong_evidence"
          WrongScope => "relation.wrong_scope"
          WrongRetention => "relation.wrong_retention"
          KeySetRole(_, _) => "relation.key_set_role"
          KeySetArity(_) => "relation.key_set_arity"
          KeySetContract(_, _) => "relation.key_set_contract"
          KeySetOrder(_, _, _) => "relation.key_set_order"
          Encoding => "relation.encoding"
          Contract(issue) =>
            match issue {
              UnknownContract => "relation.contract.unknown_contract"
              InvalidLimits => "relation.contract.invalid_limits"
              InvalidWire => "relation.contract.invalid_wire"
              InvalidObject => "relation.contract.invalid_object"
              MissingField(_) => "relation.contract.missing_field"
              UnknownField(_) => "relation.contract.unknown_field"
              InvalidField(_) => "relation.contract.invalid_field"
              IdentityAlreadyPresent =>
                "relation.contract.identity_already_present"
              IdentityMissing => "relation.contract.identity_missing"
              IdentityMismatch => "relation.contract.identity_mismatch"
              ConditionalField(_) => "relation.contract.conditional_field"
              Encoding => "relation.contract.encoding"
            }
        },
      )
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
#export_name("clientProgramOriginalModelAcquiredLookupDependencyBodies")
pub fn client_program_original_model_acquired_lookup_dependency_bodies(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> Result[
  Array[(String, String, String)],
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.client_effect_model_acquired_lookup_dependency_bodies(value).map(bodies => {
      bodies.map(body => {
        (
          @publication.captured_effect_dependency_body_kind(body),
          @publication.captured_effect_dependency_body_cid(body),
          @publication.captured_effect_dependency_body_json(body),
        )
      })
    },
  )
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

///|
/// Borrow the original Scope import bodies retained by this Model; no final
/// Run inputs, re-admission or replacement Result Artifact are synthesized.
#export_name("clientProgramOriginalModelAcquiredScopeImportBodies")
pub fn client_program_original_model_acquired_scope_import_bodies(
  value : @publication_host.ClientEffectModelAcquiredEvidence,
) -> Array[(String, String, String)] {
  @publication_host.client_effect_model_acquired_scope_import_bodies(value)
}

///|
#export_name("clientProgramPreconsumerModelUnitIdentityStartCapacity")
pub fn client_program_preconsumer_model_unit_identity_start_capacity(
  held : @infer_host.OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (Int64, Int64)? {
  @infer_host.preconsumer_model_unit_identity_start_capacity(
    held, compiled, definition, plan,
  ).map(capacity => {
    (
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    )
  })
}

///|
#export_name("clientProgramPreconsumerModelUnitIdentityStart")
pub fn client_program_preconsumer_model_unit_identity_start(
  held : @infer_host.OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> Result[
  @execution.CompletedRelationIdentityScan,
  @execution.CompletedExportIssue,
] {
  @infer_host.start_preconsumer_model_unit_identity(
    held, compiled, definition, plan,
  )
}

///|
#export_name("clientProgramPreconsumerModelUnitObservationCapacity")
pub fn client_program_preconsumer_model_unit_observation_capacity(
  held : @infer_host.OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
) -> (Int64, Int64)? {
  @infer_host.preconsumer_model_unit_observation_capacity(
    held, compiled, definition, plan, receipt, max_wire_bytes,
  ).map(capacity => {
    (
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    )
  })
}

///|
#export_name("clientProgramPrepareInstalledEffectModelUnitEvidence")
pub fn client_program_prepare_installed_effect_model_unit_evidence(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  held : @infer_host.OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @infer_host.PreconsumerModelUnitEvidence,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  let parent = match
    @client_local_host.installed_effect_model_unit_parent(
      run, plan, request, compiled, definition, graph,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  let mut failure : @client_local_host.ClientInstalledManagedRunIssue? = None
  let result = @infer_host.issue_preconsumer_original_model_acquired_evidence(
    held,
    compiled,
    definition,
    graph,
    receipt,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
    parent_ledger=Some(parent),
    before_body=Some(fn(kind, shape) {
      if failure is Some(_) {
        return false
      }
      match
        @client_local_host.reserve_installed_effect_model_unit_body(
          run, plan, request, kind, shape,
        ) {
        Ok(_) => true
        Err(issue) => {
          failure = Some(issue)
          false
        }
      }
    }),
  )
  if failure is Some(issue) {
    return Err(Run(issue))
  }
  guard @client_local_host.installed_effect_model_unit_parent(
      run, plan, request, compiled, definition, graph,
    )
    is Ok(actual) &&
    physical_equal(actual, parent) else {
    return Err(Run(Retired))
  }
  result.map_err(issue => {
    @client_local_host.ClientEffectUnitPreparationIssue::Evidence(issue)
  })
}

///|
#export_name("clientProgramPreconsumerModelUnitAcquiredEvidence")
pub fn client_program_preconsumer_model_unit_acquired_evidence(
  original : @infer_host.PreconsumerModelUnitEvidence,
) -> @publication_host.ClientEffectModelAcquiredEvidence? {
  @infer_host.preconsumer_model_unit_acquired_evidence(original)
}

///|
#export_name("clientProgramPrepareInstalledEffectModelUnitArtifact")
pub fn client_program_prepare_installed_effect_model_unit_artifact(
  run : @client_local_host.ClientInstalledManagedRun,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  owner : @publication_host.PreparedClientEffectComputation,
  original : @infer_host.PreconsumerModelUnitEvidence,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @client_local_host.ClientEffectUnitPreparationIssue,
] {
  guard @infer_host.preconsumer_model_unit_acquired_evidence(original)
    is Some(acquired) else {
    return Err(Artifact(ForeignOwner))
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let unit = @strategy.captured_effect_local_result_stage(result)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    ),
  )
  let shapes = match
    @publication_host.client_effect_model_unit_artifact_construction_geometry(
      owner, acquired, name, receipt, admission, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Artifact(issue))
  }
  for (kind, shape) in shapes {
    match
      @client_local_host.reserve_installed_effect_model_unit_body(
        run, plan, request, kind, shape,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Run(issue))
    }
  }
  // Resource resize/current callbacks may retire the original Model. Fence
  // that actual boundary before constructing even its local Definition.
  guard @infer_host.preconsumer_model_unit_acquired_evidence(original)
    is Some(same) &&
    physical_equal(same, acquired) else {
    return Err(Artifact(ForeignOwner))
  }
  let definition = match
    @publication_host.issue_client_effect_local_result_definition(
      owner, unit, name, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Artifact(ForeignDefinition))
  }
  @infer_host.issue_preconsumer_original_model_unit_artifact(
    original, owner, inputs, exported, definition, receipt, admission, max_bytes,
    max_nodes, max_depth,
  ).map_err(issue => Artifact(issue))
}
