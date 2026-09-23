///|
#export_name("salesforcePrepareWriteProjection")
pub fn salesforce_prepare_write_projection(
  observation : @catalog.CatalogObservation,
  tenant : String,
  principal : String,
  environment : String,
  connection_revision : String,
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
    tenant,
    principal,
    environment,
    connection_revision,
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
