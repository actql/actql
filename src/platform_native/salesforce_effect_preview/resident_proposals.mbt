///|
pub(all) struct NativeSalesforceTargetAccess {
  service : @resource.NativeCredentialResourceService
  grant : @credential.RemoteCredentialGrant
  use_id : String
  scope : @resource.NativeCredentialScope
  credential_org_id : String
}

///|
pub(all) enum NativeResidentEffectTargetIssue {
  InvalidLimits
  ForeignMapping
  InvalidChanges
  Request(@catalog.RecoveredWriteRequestIssue)
  Mapping(@catalog.DeclarationUseIssue)
  Provider(NativeSalesforcePreviewIssue)
  Proposal(@resident.ResidentEffectProposalIssue)
}

///|
/// Project the actual retained consumer Result through its checked mapping,
/// prepare exact Provider requests, and read the physical targets under separate
/// current observe grants. The caller retains the inputs and every credential
/// use on failure; partial observations are not a complete Preview or a write
/// permit. It must not repeat Source/Compute or silently retry consumed reads.
pub fn observe_native_resident_effect_targets(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  stage : Int,
  effect_id : String,
  local_result : Int,
  mapping : @catalog.ExecutionMapping,
  projection : @catalog.WriteProjection,
  current_catalog : @catalog.CatalogObservation,
  api_version : String,
  export_limits : @host.PublicationOutputExportLimits,
  body_limits : @catalog.WriteBodyLimits,
  request_limits : @catalog.WriteRequestLimits,
  observation_limits : @catalog.TargetObservationLimits,
  max_rows : Int,
  max_fields : Int,
  max_work : Int,
  max_utf16_units : Int,
  access : (Int, @catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeSalesforcePreviewIssue,
  ],
) -> Result[
  Array[
    (
      @catalog.SingleWriteRequest,
      String,
      @catalog.TargetObservation,
      @catalog.TargetPreviewRow,
    ),
  ],
  NativeResidentEffectTargetIssue,
] {
  if max_rows < 1 ||
    max_fields < 1 ||
    max_work < 1 ||
    max_utf16_units < 1 ||
    body_limits.max_bytes < 1 ||
    body_limits.max_nodes < 1 ||
    body_limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  guard @host.client_effect_member_descriptor(
      materials.prepared,
      stage,
      effect_id,
      max_work,
    )
    is Ok(descriptor) &&
    descriptor.2 == "update" &&
    descriptor.4 == mapping.mapping_ref &&
    descriptor.5 == mapping.mapping_cid &&
    mapping.operation is @catalog.WriteUpdateById &&
    @strategy.captured_effect_inputs_run_definition_cid(inputs) ==
    Some(@publication.publication_contract_identity(materials.run_definition)) else {
    return Err(ForeignMapping)
  }
  match @catalog.check_execution_write(mapping, projection) {
    Ok(_) => ()
    Err(issue) => return Err(Mapping(issue))
  }
  let rows : Array[
    (
      @catalog.SingleWriteRequest,
      String,
      @catalog.TargetObservation,
      @catalog.TargetPreviewRow,
    ),
  ] = []
  let mut failure : NativeResidentEffectTargetIssue? = None
  let receive = (index : Int, selector : String, changes : String) => {
    let acquire = () => {
      if index != rows.length() || index >= max_rows {
        return Err(NativeResidentEffectTargetIssue::InvalidLimits)
      }
      let body = try {
        let source = match
          @source.parse_json_bytes_preserving(@utf8.encode(changes), {
            max_input_bytes: body_limits.max_bytes,
            max_nodes: body_limits.max_nodes,
            max_depth: body_limits.max_depth,
          }) {
          Ok(value) => value
          Err(_) => return Err(InvalidChanges)
        }
        let value = @canonical.from_source(
          source,
          body_limits.max_nodes,
          body_limits.max_depth,
          body_limits.max_bytes,
          data_keys=true,
        )
        guard @canonical.object_field_count(value) == Some(2) &&
          @canonical.object_field(value, "state")
          is Some(@canonical.String("present")) &&
          @canonical.object_field(value, "value") is Some(body) else {
          return Err(InvalidChanges)
        }
        @canonical.stringify_value(
          body,
          body_limits.max_bytes,
          body_limits.max_nodes,
          body_limits.max_depth,
        )
      } catch {
        _ => return Err(InvalidChanges)
      }
      let request = match
        @catalog.recover_single_write_request(
          projection, body, selector, api_version, body_limits, request_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Request(issue))
      }
      match @catalog.check_execution_single_write(mapping, request) {
        Ok(_) => ()
        Err(issue) => return Err(Mapping(issue))
      }
      let granted = match access(index, request) {
        Ok(value) => value
        Err(issue) => return Err(Provider(issue))
      }
      let (use_cid, observation, row) = match
        observe_native_salesforce_effect_target(
          granted.service,
          granted.grant,
          granted.use_id,
          granted.scope,
          granted.credential_org_id,
          request,
          current_catalog,
          observation_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Provider(issue))
      }
      rows.push((request, use_cid, observation, row))
      Ok(())
    }
    match acquire() {
      Ok(_) => Ok(())
      Err(issue) => {
        failure = Some(issue)
        Err(())
      }
    }
  }
  let result = consumer.read_effect_proposals(
    inputs,
    descriptor.0,
    local_result,
    export_limits,
    max_fields,
    max_work,
    body_limits.max_bytes,
    body_limits.max_nodes,
    body_limits.max_depth,
    max_utf16_units,
    receive,
  )
  match result {
    Ok(count) if count == rows.length() => Ok(rows)
    Ok(_) => Err(InvalidChanges)
    Err(@resident.ReceiverRejected) =>
      match failure {
        Some(issue) => Err(issue)
        None => Err(InvalidChanges)
      }
    Err(issue) => Err(Proposal(issue))
  }
}
