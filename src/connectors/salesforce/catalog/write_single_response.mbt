///|
pub(all) enum WriteSingleKind {
  SingleCreate
  SingleUpdateById(String)
  SingleUpsert
} derive(Eq, Debug)

///|
pub(all) enum WriteSingleResponseIssue {
  InvalidLimits
  BudgetExceeded
  UnexpectedStatus
  InvalidResponse
} derive(Eq, Debug)

///|
/// One complete successful single-record REST response. A rejected or missing
/// response is not classified here; transport settlement owns uncertainty.
pub struct WriteSingleResponse {
  result : WriteRowResult
  response_sha256 : String
}

///|
pub fn write_single_result(value : WriteSingleResponse) -> WriteRowResult {
  value.result
}

///|
pub fn write_single_response_sha256(value : WriteSingleResponse) -> String {
  value.response_sha256
}

///|
pub fn project_write_single_success(
  http_status : Int,
  bytes : Bytes,
  kind : WriteSingleKind,
  limits : WriteCollectionResponseLimits,
) -> Result[WriteSingleResponse, WriteSingleResponseIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if kind is SingleUpdateById(target_id) {
    if target_id.is_empty() || http_status != 204 {
      return Err(UnexpectedStatus)
    }
    if bytes.length() != 0 {
      return Err(InvalidResponse)
    }
    return Ok({
      result: RowApplied(target_id, false),
      response_sha256: @sha.hex(bytes),
    })
  }
  match kind {
    SingleCreate => if http_status != 201 { return Err(UnexpectedStatus) }
    SingleUpsert =>
      if http_status != 200 && http_status != 201 {
        return Err(UnexpectedStatus)
      }
    SingleUpdateById(_) => abort("handled above")
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
  let collection_kind = match kind {
    SingleCreate => CollectionCreate
    SingleUpsert => CollectionUpsert
    SingleUpdateById(_) => abort("handled above")
  }
  let result = match collection_result(root, collection_kind) {
    Ok(RowApplied(id, created)) => {
      if kind is SingleUpsert && created != (http_status == 201) {
        return Err(InvalidResponse)
      }
      RowApplied(id, created)
    }
    _ => return Err(InvalidResponse)
  }
  Ok({ result, response_sha256: @sha.hex(bytes), })
}
