///|
#export_name("salesforcePrepareWriteProjection")
pub fn salesforce_prepare_write_projection(
  observation : @catalog.CatalogObservation,
  namespace_id : String,
  principal : String,
  environment : String,
  connection_revision : String,
  org_id : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
  sync_occurrence : String,
  resource_name : String,
  operation_code : Int,
  external_id_field : String,
  field_names : Array[String],
  max_fields : Int,
) -> @catalog.WriteProjection raise SalesforceCatalogBridgeIssue {
  let binding : @catalog.CatalogObservationBinding = {
    namespace_id,
    principal,
    environment,
    connection_revision,
    org_id,
    site_key,
    site_generation,
    connector_registration,
    connector_revision,
    resource_origin,
    run_invocation_cid,
    dispatch_request_cid,
    sync_occurrence,
  }
  let operation = match operation_code {
    0 => @catalog.WriteCreate
    1 => @catalog.WriteUpdateById
    2 if !external_id_field.is_empty() =>
      @catalog.WriteUpsertByExternalId(external_id_field)
    _ => raise InvalidResource
  }
  match
    @catalog.prepare_write_projection(
      observation, binding, resource_name, operation, field_names, max_fields,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteProjection(issue)
  }
}

///|
#export_name("salesforceRecheckWriteProjection")
pub fn salesforce_recheck_write_projection(
  projection : @catalog.WriteProjection,
  current : @catalog.CatalogObservation,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.recheck_write_projection(projection, current) {
    Ok(_) => true
    Err(issue) => raise WriteProjection(issue)
  }
}

///|
#export_name("salesforcePrepareWriteBody")
pub fn salesforce_prepare_write_body(
  projection : @catalog.WriteProjection,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteBody raise SalesforceCatalogBridgeIssue {
  match
    @catalog.prepare_write_body(projection, bytes, {
      max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) => raise WriteBody(issue)
  }
}

///|
#export_name("salesforcePrepareSingleWriteRequest")
pub fn salesforce_prepare_single_write_request(
  body : @catalog.WriteBody,
  api_version : String,
  target_code : Int,
  target_text : String,
  target_int : Int,
  max_path_bytes : Int,
  max_target_bytes : Int,
  max_body_bytes : Int,
) -> @catalog.SingleWriteRequest raise SalesforceCatalogBridgeIssue {
  let target = match target_code {
    0 => @catalog.NoWriteTarget
    1 => @catalog.RecordId(target_text)
    2 => @catalog.ExternalText(target_text)
    3 => @catalog.ExternalInt(target_int)
    _ => raise InvalidResource
  }
  match
    @catalog.prepare_single_write_request(body, api_version, target, {
      max_path_bytes,
      max_target_bytes,
      max_body_bytes,
    }) {
    Ok(value) => value
    Err(issue) => raise WriteRequest(issue)
  }
}

///|
/// Re-admit the private Preview inside this connector bundle. This is only
/// identity admission; current apply and credential authority stay separate.
#export_name("salesforceAdmitRecoveryPreview")
pub fn salesforce_admit_recovery_preview(
  wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.EffectPreviewIdentity raise SalesforceCatalogBridgeIssue {
  match
    @publication.admit_effect_preview_identity(
      wire, expected_run_identity_cid, expected_authoring_context_cid, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => raise RecoveryPreview(issue)
  }
}

///|
#export_name("salesforceRecoveryPreviewMemberCount")
pub fn salesforce_recovery_preview_member_count(
  preview : @publication.EffectPreviewIdentity,
) -> Int {
  @publication.effect_preview_member_count(preview)
}

///|
#export_name("salesforceRecoveryPreviewRowCount")
pub fn salesforce_recovery_preview_row_count(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
) -> Int? {
  @publication.effect_preview_row_count(preview, member_index)
}

///|
/// Use an identity admitted in this connector bundle. Provider request
/// material is rebuilt once per row without reading the captured data again.
#export_name("salesforceRecoverSingleWriteRequest")
pub fn salesforce_recover_single_write_request(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  ordered_row_index : Int,
  projection : @catalog.WriteProjection,
  api_version : String,
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
  max_path_bytes : Int,
  max_target_bytes : Int,
  max_request_body_bytes : Int,
  max_identity_bytes : Int,
  resource_origin : String,
  expected_request_cid : String,
) -> @catalog.SingleWriteRequest raise SalesforceCatalogBridgeIssue {
  guard @publication.effect_preview_ordered_row_identity(
      preview, member_index, ordered_row_index,
    )
    is Some(row_cid) &&
    @publication.effect_preview_row_index(preview, member_index, row_cid)
    is Some(change_index) &&
    @publication.effect_preview_ordered_row_intended_value_wire(
      preview, member_index, ordered_row_index,
    )
    is Some(body_wire) &&
    @publication.effect_preview_ordered_row_correlation_wire(
      preview, member_index, ordered_row_index,
    )
    is Some(correlation_wire) else {
    raise InvalidResource
  }
  let request = match
    @catalog.recover_single_write_request(
      projection,
      body_wire,
      correlation_wire,
      api_version,
      {
        max_bytes: max_body_bytes,
        max_nodes: max_body_nodes,
        max_depth: max_body_depth,
      },
      {
        max_path_bytes,
        max_target_bytes,
        max_body_bytes: max_request_body_bytes,
      },
    ) {
    Ok(value) => value
    Err(issue) => raise RecoveredWriteRequest(issue)
  }
  if @publication.effect_preview_member_kind(preview, member_index) !=
    Some(@catalog.single_write_request_effect_kind(request)) ||
    !salesforce_single_write_request_matches_preview_footprint(
      preview, member_index, change_index, request, max_identity_bytes,
    ) {
    raise InvalidResource
  }
  let actual_request_cid = match
    @catalog.single_write_request_cid(
      request, resource_origin, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteRequest(issue)
  }
  if actual_request_cid != expected_request_cid {
    raise ForeignRecoveredRequest
  }
  request
}

///|
#export_name("salesforceSingleWriteRequestMethod")
pub fn salesforce_single_write_request_method(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_method(request)
}

///|
#export_name("salesforceSingleWriteRequestPath")
pub fn salesforce_single_write_request_path(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_path(request)
}

///|
#export_name("salesforceSingleWriteRequestBody")
pub fn salesforce_single_write_request_body(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_body(request)
}

///|
/// The request's row as ActQL values: the Preview's value of this row.
#export_name("salesforceSingleWriteRequestValue")
pub fn salesforce_single_write_request_value(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_value(request)
}

///|
#export_name("salesforceSingleWriteRequestOrgId")
pub fn salesforce_single_write_request_org_id(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_org_id(request)
}

///|
#export_name("salesforceSingleWriteRequestTargetIdentity")
pub fn salesforce_single_write_request_target_identity(
  request : @catalog.SingleWriteRequest,
  max_identity_bytes : Int,
) -> @catalog.WriteTargetIdentity? raise SalesforceCatalogBridgeIssue {
  match
    @catalog.single_write_request_target_identity(request, max_identity_bytes) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
#export_name("salesforceSingleWriteRequestBoundaryCid")
pub fn salesforce_single_write_request_boundary_cid(
  request : @catalog.SingleWriteRequest,
  max_identity_bytes : Int,
) -> String raise SalesforceCatalogBridgeIssue {
  match
    @catalog.single_write_request_boundary_cid(request, max_identity_bytes) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
/// One bounded MoonBit-owned footprint for the requests of one Effect member.
/// This is a conflict fact, not an apply permission.
#export_name("salesforceSingleWriteMemberFootprint")
pub fn salesforce_single_write_member_footprint(
  requests : Array[@catalog.SingleWriteRequest],
  max_rows : Int,
  max_identity_bytes : Int,
) -> (String, String, String, String, String, Array[String]) raise SalesforceCatalogBridgeIssue {
  match
    @catalog.single_write_member_footprint(
      requests, max_rows, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
/// Check that one admitted physical REST request is among the target facts
/// claimed by its private Preview member. Whole-set footprint admission,
/// source-to-payload equivalence, and current apply authority remain separate.
#export_name("salesforceSingleWriteRequestMatchesPreviewFootprint")
pub fn salesforce_single_write_request_matches_preview_footprint(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  request : @catalog.SingleWriteRequest,
  max_identity_bytes : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  guard @publication.effect_preview_member_footprint(preview, member_index)
    is Some(footprint) else {
    return false
  }
  if @publication.effect_preview_row_intended_value_wire(
      preview, member_index, row_index,
    ) !=
    Some(@catalog.single_write_request_value(request)) {
    return false
  }
  if @publication.effect_preview_footprint_provider_namespace(footprint) !=
    "salesforce" ||
    @publication.effect_preview_footprint_resource_kind(footprint) !=
    @catalog.single_write_request_resource(request) {
    return false
  }
  let boundary = salesforce_single_write_request_boundary_cid(
    request, max_identity_bytes,
  )
  if @publication.effect_preview_footprint_provider_boundary_cid(footprint) !=
    boundary {
    return false
  }
  match
    salesforce_single_write_request_target_identity(request, max_identity_bytes) {
    None =>
      (
        @publication.effect_preview_footprint_kind(footprint) == "collection" ||
        @publication.effect_preview_footprint_kind(footprint) == "opaque"
      ) &&
      @publication.effect_preview_footprint_target_count(footprint) == 0
    Some(target) => {
      if @publication.effect_preview_footprint_kind(footprint) !=
        "exact_targets" ||
        @publication.effect_preview_footprint_resource_identity_scheme_cid(
          footprint,
        ) !=
        @catalog.write_target_scheme_cid(target) {
        return false
      }
      for
        index in 0..<@publication.effect_preview_footprint_target_count(
          footprint,
        ) {
        if @publication.effect_preview_footprint_target_cid(footprint, index) ==
          Some(@catalog.write_target_object_cid(target)) {
          guard @publication.effect_preview_row_correlation_wire(
              preview, member_index, row_index,
            )
            is Some(correlation) else {
            return false
          }
          return match
            @catalog.single_write_request_matches_preview_row_target(
              request, correlation, max_identity_bytes,
            ) {
            Ok(value) => value
            Err(issue) => raise WriteCollectionRequest(issue)
          }
        }
      }
      false
    }
  }
}

///|
#export_name("salesforceSingleWriteRequestGrantOperation")
pub fn salesforce_single_write_request_grant_operation(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_grant_operation(request)
}

///|
#export_name("salesforceSingleWriteRequestEffectKind")
pub fn salesforce_single_write_request_effect_kind(
  request : @catalog.SingleWriteRequest,
) -> String {
  @catalog.single_write_request_effect_kind(request)
}

///|
#export_name("salesforceSingleWriteRequestCid")
pub fn salesforce_single_write_request_cid(
  request : @catalog.SingleWriteRequest,
  resource_origin : String,
  max_wire_bytes : Int,
) -> String raise SalesforceCatalogBridgeIssue {
  match
    @catalog.single_write_request_cid(request, resource_origin, max_wire_bytes) {
    Ok(cid) => cid
    Err(issue) => raise WriteRequest(issue)
  }
}

///|
#export_name("salesforceRecheckSingleWriteRequest")
pub fn salesforce_recheck_single_write_request(
  request : @catalog.SingleWriteRequest,
  current : @catalog.CatalogObservation,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.recheck_single_write_request(request, current) {
    Ok(_) => true
    Err(issue) => raise WriteProjection(issue)
  }
}

///|
/// Interpret one bounded target read under the exact prepared request. A
/// missing or foreign record cannot become an update-side Preview guard.
#export_name("salesforcePrepareTargetObservation")
pub fn salesforce_prepare_target_observation(
  request : @catalog.SingleWriteRequest,
  status : Int,
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_identity_bytes : Int,
) -> @catalog.TargetObservation raise SalesforceCatalogBridgeIssue {
  match
    @catalog.prepare_target_observation(request, status, body, {
      max_bytes,
      max_nodes,
      max_depth,
      max_identity_bytes,
    }) {
    Ok(value) => value
    Err(issue) => raise TargetObservation(issue)
  }
}

///|
#export_name("salesforceTargetObservationVersionCid")
pub fn salesforce_target_observation_version_cid(
  value : @catalog.TargetObservation,
) -> String {
  @catalog.target_observation_version_cid(value)
}

///|
#export_name("salesforceTargetObservationBeforeValueWire")
pub fn salesforce_target_observation_before_value_wire(
  value : @catalog.TargetObservation,
) -> String {
  @catalog.target_observation_before_value_wire(value)
}

///|
/// Bind one update-side Preview row to the same request that yielded the
/// target observation. The caller still verifies checked input and authority.
#export_name("salesforcePrepareObservedPreviewRow")
pub fn salesforce_prepare_observed_preview_row(
  request : @catalog.SingleWriteRequest,
  observation : @catalog.TargetObservation,
  max_identity_bytes : Int,
) -> @catalog.TargetPreviewRow raise SalesforceCatalogBridgeIssue {
  match
    @catalog.prepare_observed_target_preview_row(
      request, observation, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise TargetObservation(issue)
  }
}

///|
#export_name("salesforceObservedPreviewRowFields")
pub fn salesforce_observed_preview_row_fields(
  value : @catalog.TargetPreviewRow,
) -> Array[String] {
  [
    @catalog.target_preview_row_target_wire(value),
    @catalog.target_preview_row_guard_cid(value),
    @catalog.target_preview_row_before_wire(value),
    @catalog.target_preview_row_after_wire(value),
    @catalog.target_preview_row_changes_wire(value),
  ]
}

///|
#export_name("salesforceTargetObservationResponseSha256")
pub fn salesforce_target_observation_response_sha256(
  value : @catalog.TargetObservation,
) -> String {
  @catalog.target_observation_response_sha256(value)
}

///|
#export_name("salesforceSingleWriteRequestScopeMatches")
pub fn salesforce_single_write_request_scope_matches(
  request : @catalog.SingleWriteRequest,
  namespace_id : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  @catalog.single_write_request_matches_site_scope(
    request, namespace_id, principal, environment, site_key, site_generation, connector_registration,
    connector_revision, resource_origin, run_invocation_cid, dispatch_request_cid,
  )
}

///|
#export_name("salesforceProjectSingleWriteSuccess")
pub fn salesforce_project_single_write_success(
  request : @catalog.SingleWriteRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteSingleResponse raise SalesforceCatalogBridgeIssue {
  match
    @catalog.project_write_single_success(
      status,
      bytes,
      @catalog.single_write_request_kind(request),
      { max_bytes, max_nodes, max_depth, max_rows: 1, },
    ) {
    Ok(value) => value
    Err(issue) => raise WriteSingleResponse(issue)
  }
}

///|
/// A single-record response that is not a success: a definite failure only
/// on documented rejection evidence for this request, else an issue (the
/// write stays unknown).
#export_name("salesforceProjectSingleWriteRejection")
pub fn salesforce_project_single_write_rejection(
  request : @catalog.SingleWriteRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteSingleResponse raise SalesforceCatalogBridgeIssue {
  match
    @catalog.project_write_single_rejection(status, bytes, request, {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows: 1,
    }) {
    Ok(value) => value
    Err(issue) => raise WriteSingleResponse(issue)
  }
}

///|
#export_name("salesforceSingleWriteSuccessProjection")
pub fn salesforce_single_write_success_projection(
  response : @catalog.WriteSingleResponse,
) -> Array[String] raise SalesforceCatalogBridgeIssue {
  match @catalog.write_single_result(response) {
    @catalog.RowApplied(id, created) =>
      [
        id,
        if created {
          "created"
        } else {
          "updated"
        },
        @catalog.write_single_response_sha256(response),
      ]
    @catalog.RowFailed(_) => raise InvalidResource
  }
}

///|
#export_name("salesforceProjectSingleEffectOutcome")
pub fn salesforce_project_single_effect_outcome(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  request : @catalog.SingleWriteRequest,
  response : @catalog.WriteSingleResponse,
  max_identity_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteRowEffectProjection raise SalesforceCatalogBridgeIssue {
  if !salesforce_single_write_request_matches_preview_footprint(
      preview, member_index, row_index, request, max_identity_bytes,
    ) {
    raise InvalidResource
  }
  guard @publication.effect_preview_row_identity(
      preview, member_index, row_index,
    )
    is Some(row_cid) else {
    raise InvalidResource
  }
  match
    @catalog.project_single_effect_outcome(
      response, row_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) =>
      match
        @publication.check_effect_preview_row_outcome(
          preview,
          member_index,
          row_index,
          @catalog.write_row_effect_projection_row_cid(value),
          @catalog.write_row_effect_projection_wire(value),
          max_wire_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(_) => value
        Err(_) => raise InvalidResource
      }
    Err(issue) => raise WriteCollectionResponse(issue)
  }
}

///|
#export_name("salesforcePrepareContinueWriteCollection")
pub fn salesforce_prepare_continue_write_collection(
  row_preview_cids : Array[String],
  bodies : Array[@catalog.WriteBody],
  target_codes : Array[Int],
  target_texts : Array[String],
  target_ints : Array[Int],
  api_version : String,
  max_path_bytes : Int,
  max_target_bytes : Int,
  max_body_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
) -> @catalog.WriteCollectionRequest raise SalesforceCatalogBridgeIssue {
  if row_preview_cids.length() != bodies.length() ||
    bodies.length() != target_codes.length() ||
    bodies.length() != target_texts.length() ||
    bodies.length() != target_ints.length() ||
    bodies.length() > max_rows {
    raise InvalidResource
  }
  let rows : Array[@catalog.WriteCollectionItem] = []
  for index in 0..<bodies.length() {
    let target = match target_codes[index] {
      0 => @catalog.NoWriteTarget
      1 => @catalog.RecordId(target_texts[index])
      2 => @catalog.ExternalText(target_texts[index])
      3 => @catalog.ExternalInt(target_ints[index])
      _ => raise InvalidResource
    }
    rows.push({
      row_preview_cid: row_preview_cids[index],
      body: bodies[index],
      target,
    })
  }
  match
    @catalog.prepare_continue_write_collection(rows, api_version, {
      max_path_bytes,
      max_target_bytes,
      max_body_bytes,
      max_nodes,
      max_depth,
      max_rows,
    }) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
#export_name("salesforcePrepareWriteTargetIdentity")
pub fn salesforce_prepare_write_target_identity(
  projection : @catalog.WriteProjection,
  target_code : Int,
  target_text : String,
  target_int : Int,
  max_target_bytes : Int,
  max_identity_bytes : Int,
) -> @catalog.WriteTargetIdentity raise SalesforceCatalogBridgeIssue {
  let target = match target_code {
    1 => @catalog.RecordId(target_text)
    2 => @catalog.ExternalText(target_text)
    3 => @catalog.ExternalInt(target_int)
    _ => raise InvalidResource
  }
  match
    @catalog.prepare_write_target_identity(
      projection, target, max_target_bytes, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
#export_name("salesforceWriteTargetBoundaryCid")
pub fn salesforce_write_target_boundary_cid(
  value : @catalog.WriteTargetIdentity,
) -> String {
  @catalog.write_target_boundary_cid(value)
}

///|
#export_name("salesforceWriteTargetSchemeCid")
pub fn salesforce_write_target_scheme_cid(
  value : @catalog.WriteTargetIdentity,
) -> String {
  @catalog.write_target_scheme_cid(value)
}

///|
#export_name("salesforceWriteTargetObjectCid")
pub fn salesforce_write_target_object_cid(
  value : @catalog.WriteTargetIdentity,
) -> String {
  @catalog.write_target_object_cid(value)
}

///|
#export_name("salesforceCollectionWriteRequestMethod")
pub fn salesforce_collection_write_request_method(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_method(request)
}

///|
#export_name("salesforceCollectionWriteRequestPath")
pub fn salesforce_collection_write_request_path(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_path(request)
}

///|
#export_name("salesforceCollectionWriteRequestBody")
pub fn salesforce_collection_write_request_body(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_body(request)
}

///|
#export_name("salesforceCollectionWriteRequestOrgId")
pub fn salesforce_collection_write_request_org_id(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_org_id(request)
}

///|
#export_name("salesforceCollectionWriteRequestTargetIdentity")
pub fn salesforce_collection_write_request_target_identity(
  request : @catalog.WriteCollectionRequest,
  index : Int,
  max_identity_bytes : Int,
) -> @catalog.WriteTargetIdentity? raise SalesforceCatalogBridgeIssue {
  match
    @catalog.write_collection_request_target_identity(
      request, index, max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
#export_name("salesforceCollectionWriteRequestBoundaryCid")
pub fn salesforce_collection_write_request_boundary_cid(
  request : @catalog.WriteCollectionRequest,
  max_identity_bytes : Int,
) -> String raise SalesforceCatalogBridgeIssue {
  match
    @catalog.write_collection_request_boundary_cid(request, max_identity_bytes) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionRequest(issue)
  }
}

///|
/// A Collections batch may cover a subset of one admitted member's rows,
/// but every exact target in that batch must belong to that member's Preview.
#export_name("salesforceCollectionWriteRequestMatchesPreviewFootprint")
pub fn salesforce_collection_write_request_matches_preview_footprint(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  first_row : Int,
  request : @catalog.WriteCollectionRequest,
  max_identity_bytes : Int,
  max_binding_work : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  guard max_binding_work > 0 &&
    first_row >= 0 &&
    @publication.effect_preview_member_footprint(preview, member_index)
    is Some(footprint) &&
    @publication.effect_preview_row_count(preview, member_index)
    is Some(preview_count) else {
    return false
  }
  if @publication.effect_preview_footprint_provider_namespace(footprint) !=
    "salesforce" ||
    @publication.effect_preview_footprint_resource_kind(footprint) !=
    @catalog.write_collection_request_resource(request) ||
    @publication.effect_preview_footprint_provider_boundary_cid(footprint) !=
    salesforce_collection_write_request_boundary_cid(
      request, max_identity_bytes,
    ) {
    return false
  }
  let count = @catalog.write_collection_request_row_count(request)
  if first_row > preview_count || count > preview_count - first_row {
    return false
  }
  let target_count = @publication.effect_preview_footprint_target_count(
    footprint,
  )
  let mut remaining = max_binding_work
  for row in 0..<count {
    remaining -= 1
    if remaining < 0 {
      return false
    }
    guard @publication.effect_preview_ordered_row_intended_value_wire(
        preview,
        member_index,
        first_row + row,
      ) ==
      @catalog.write_collection_request_row_body(request, row) else {
      return false
    }
    let target = salesforce_collection_write_request_target_identity(
      request, row, max_identity_bytes,
    )
    match target {
      None =>
        if !(@publication.effect_preview_footprint_kind(footprint) ==
          "collection" ||
          @publication.effect_preview_footprint_kind(footprint) == "opaque") ||
          target_count != 0 {
          return false
        }
      Some(identity) => {
        if @publication.effect_preview_footprint_kind(footprint) !=
          "exact_targets" ||
          @publication.effect_preview_footprint_resource_identity_scheme_cid(
            footprint,
          ) !=
          @catalog.write_target_scheme_cid(identity) {
          return false
        }
        let mut found = false
        for index in 0..<target_count {
          remaining -= 1
          if remaining < 0 {
            return false
          }
          if @publication.effect_preview_footprint_target_cid(footprint, index) ==
            Some(@catalog.write_target_object_cid(identity)) {
            found = true
            break
          }
        }
        if !found {
          return false
        }
        guard @publication.effect_preview_ordered_row_correlation_wire(
            preview,
            member_index,
            first_row + row,
          )
          is Some(correlation) else {
          return false
        }
        match
          @catalog.write_collection_request_matches_preview_row_target(
            request, row, correlation, max_identity_bytes,
          ) {
          Ok(true) => ()
          Ok(false) => return false
          Err(issue) => raise WriteCollectionRequest(issue)
        }
      }
    }
  }
  true
}

///|
#export_name("salesforceCollectionWriteRequestGrantOperation")
pub fn salesforce_collection_write_request_grant_operation(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_grant_operation(request)
}

///|
#export_name("salesforceCollectionWriteRequestEffectKind")
pub fn salesforce_collection_write_request_effect_kind(
  request : @catalog.WriteCollectionRequest,
) -> String {
  @catalog.write_collection_request_effect_kind(request)
}

///|
#export_name("salesforceCollectionWriteRequestRowCount")
pub fn salesforce_collection_write_request_row_count(
  request : @catalog.WriteCollectionRequest,
) -> Int {
  @catalog.write_collection_request_row_count(request)
}

///|
#export_name("salesforceCollectionWriteRequestRowCid")
pub fn salesforce_collection_write_request_row_cid(
  request : @catalog.WriteCollectionRequest,
  index : Int,
) -> String? {
  @catalog.write_collection_request_row_cid(request, index)
}

///|
#export_name("salesforceCollectionWriteRequestCid")
pub fn salesforce_collection_write_request_cid(
  request : @catalog.WriteCollectionRequest,
  resource_origin : String,
  max_wire_bytes : Int,
) -> String raise SalesforceCatalogBridgeIssue {
  match
    @catalog.write_collection_request_cid(
      request, resource_origin, max_wire_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteRequest(issue)
  }
}

///|
#export_name("salesforceCollectionWriteRequestScopeMatches")
pub fn salesforce_collection_write_request_scope_matches(
  request : @catalog.WriteCollectionRequest,
  namespace_id : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  @catalog.write_collection_request_matches_site_scope(
    request, namespace_id, principal, environment, site_key, site_generation, connector_registration,
    connector_revision, resource_origin, run_invocation_cid, dispatch_request_cid,
  )
}

///|
#export_name("salesforceRecheckCollectionWriteRequest")
pub fn salesforce_recheck_collection_write_request(
  request : @catalog.WriteCollectionRequest,
  current : @catalog.CatalogObservation,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.recheck_write_collection_request(request, current) {
    Ok(_) => true
    Err(issue) => raise WriteProjection(issue)
  }
}

///|
#export_name("salesforceProjectCollectionWriteResponse")
pub fn salesforce_project_collection_write_response(
  request : @catalog.WriteCollectionRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
) -> @catalog.WriteCollectionResponse raise SalesforceCatalogBridgeIssue {
  match
    @catalog.project_write_collection_response_for_request(
      status,
      bytes,
      request,
      { max_bytes, max_nodes, max_depth, max_rows, },
    ) {
    Ok(value) => value
    Err(issue) => raise WriteCollectionResponse(issue)
  }
}

///|
#export_name("salesforceCollectionWriteResponseRowCount")
pub fn salesforce_collection_write_response_row_count(
  response : @catalog.WriteCollectionResponse,
) -> Int {
  @catalog.write_collection_result_count(response)
}

///|
#export_name("salesforceCollectionWriteResponseRowApplied")
pub fn salesforce_collection_write_response_row_applied(
  response : @catalog.WriteCollectionResponse,
  index : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.write_collection_bound_result_at(response, index) {
    Some((_, @catalog.RowApplied(_, _))) => true
    Some((_, @catalog.RowFailed(_))) => false
    None => raise InvalidResource
  }
}

///|
#export_name("salesforceCollectionWriteResponseRowCid")
pub fn salesforce_collection_write_response_row_cid(
  response : @catalog.WriteCollectionResponse,
  index : Int,
) -> String raise SalesforceCatalogBridgeIssue {
  match @catalog.write_collection_bound_result_at(response, index) {
    Some((cid, _)) => cid
    None => raise InvalidResource
  }
}

///|
#export_name("salesforceProjectCollectionEffectOutcome")
pub fn salesforce_project_collection_effect_outcome(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  first_row_index : Int,
  response : @catalog.WriteCollectionResponse,
  index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @catalog.WriteRowEffectProjection raise SalesforceCatalogBridgeIssue {
  if first_row_index < 0 || index < 0 || first_row_index > 2147483647 - index {
    raise InvalidResource
  }
  match
    @catalog.project_collection_effect_outcome_at(
      response, index, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) =>
      match
        @publication.check_effect_preview_row_outcome(
          preview,
          member_index,
          first_row_index + index,
          @catalog.write_row_effect_projection_row_cid(value),
          @catalog.write_row_effect_projection_wire(value),
          max_wire_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(_) => value
        Err(_) => raise InvalidResource
      }
    Err(issue) => raise WriteCollectionResponse(issue)
  }
}

///|
#export_name("salesforceWriteEffectOutcomeRowCid")
pub fn salesforce_write_effect_outcome_row_cid(
  projection : @catalog.WriteRowEffectProjection,
) -> String {
  @catalog.write_row_effect_projection_row_cid(projection)
}

///|
#export_name("salesforceWriteEffectOutcomeWire")
pub fn salesforce_write_effect_outcome_wire(
  projection : @catalog.WriteRowEffectProjection,
) -> String {
  @catalog.write_row_effect_projection_wire(projection)
}

///|
#export_name("salesforceWriteEffectOutcomeResponseSha256")
pub fn salesforce_write_effect_outcome_response_sha256(
  projection : @catalog.WriteRowEffectProjection,
) -> String {
  @catalog.write_row_effect_projection_response_sha256(projection)
}
