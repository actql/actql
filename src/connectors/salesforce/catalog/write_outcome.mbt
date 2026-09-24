///|
pub struct WriteRowEffectProjection {
  row_preview_cid : String
  outcome_wire : String
  response_sha256 : String
}

///|
pub fn write_row_effect_projection_row_cid(
  value : WriteRowEffectProjection,
) -> String {
  value.row_preview_cid
}

///|
pub fn write_row_effect_projection_wire(
  value : WriteRowEffectProjection,
) -> String {
  value.outcome_wire
}

///|
pub fn write_row_effect_projection_response_sha256(
  value : WriteRowEffectProjection,
) -> String {
  value.response_sha256
}

///|
/// Project one typed provider result into the common EffectOutcome shape.
/// This is not physical custody or authority to advance a ledger head.
fn project_write_row_effect_outcome(
  row_preview_cid : String,
  result : WriteRowResult,
  response_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[WriteRowEffectProjection, WriteCollectionResponseIssue] {
  if max_wire_bytes < 1 ||
    max_wire_bytes > 1000000 ||
    max_nodes < 10 ||
    max_nodes > 10000 ||
    max_depth < 5 ||
    max_depth > 32 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  let outcome_wire = try {
    @encode.begin_object(writer)
    match result {
      RowApplied(record_id, created) => {
        @encode.key(writer, "result")
        @encode.begin_object(writer)
        @encode.key(writer, "created")
        @encode.bool_value(writer, created)
        @encode.key(writer, "record_id")
        @encode.string_value(writer, record_id)
        @encode.end_object(writer)
        @encode.key(writer, "state")
        @encode.string_value(writer, "applied")
      }
      RowFailed(errors) => {
        @encode.key(writer, "error")
        @encode.begin_object(writer)
        @encode.key(writer, "code")
        @encode.string_value(writer, "SalesforceRowFailed")
        @encode.key(writer, "details")
        @encode.begin_object(writer)
        @encode.key(writer, "errors")
        @encode.begin_array(writer)
        for error in errors {
          @encode.begin_object(writer)
          @encode.key(writer, "fields")
          @encode.begin_array(writer)
          for field in error.fields {
            @encode.string_value(writer, field)
          }
          @encode.end_array(writer)
          @encode.key(writer, "message")
          @encode.string_value(writer, error.message)
          @encode.key(writer, "status_code")
          @encode.string_value(writer, error.status_code)
          @encode.end_object(writer)
        }
        @encode.end_array(writer)
        @encode.end_object(writer)
        @encode.key(writer, "message")
        @encode.string_value(writer, "Salesforce row failed")
        @encode.end_object(writer)
        @encode.key(writer, "state")
        @encode.string_value(writer, "failed")
      }
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(BudgetExceeded)
  }
  Ok({ row_preview_cid, outcome_wire, response_sha256, })
}

///|
pub fn project_collection_effect_outcome_at(
  response : WriteCollectionResponse,
  index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[WriteRowEffectProjection, WriteCollectionResponseIssue] {
  guard write_collection_bound_result_at(response, index)
    is Some((row_preview_cid, result)) else {
    return Err(InvalidResponse)
  }
  project_write_row_effect_outcome(
    row_preview_cid,
    result,
    write_collection_response_sha256(response),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// A single-record success has one typed provider row. Its Preview identity
/// must come from the admitted Effect owner, not from the physical response.
pub fn project_single_effect_outcome(
  response : WriteSingleResponse,
  row_preview_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[WriteRowEffectProjection, WriteCollectionResponseIssue] {
  match write_single_result(response) {
    RowApplied(_, _) =>
      project_write_row_effect_outcome(
        row_preview_cid,
        write_single_result(response),
        write_single_response_sha256(response),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
    RowFailed(_) => Err(InvalidResponse)
  }
}
