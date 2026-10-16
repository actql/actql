///|
/// These are local request preparation bounds, not an adopted physical profile.
pub(all) struct RecordRequestLimits {
  max_rows : Int
  max_properties : Int
  max_trace_bytes : Int
  max_body_bytes : Int
  max_body_nodes : Int
  max_body_depth : Int
}

///|
pub(all) enum RecordRequestIssue {
  InvalidLimits
  BudgetExceeded
  InvalidTarget
  Property(PropertyIssue)
  Value(WriteBodyIssue)
  ForeignCatalog
  MissingTarget
  UnexpectedTarget
  ForeignTargetKey
  DuplicateTarget
  InvalidTrace
  DuplicateTrace
  InvalidMarker
  MarkerConflict
} derive(Eq, Debug)

///|
/// A typed selector observation under the original Catalog, never a grant or
/// evidence that a matching record exists. The top-level id is independent
/// from property uniqueness; other selectors need the existing unique Owner.
pub struct RecordTarget {
  priv catalog : PropertyCatalog
  key : String
  value_wire : String
  provider_value : String
}

///|
pub(all) enum RecordWriteOperation {
  Create
  Update
  Upsert(String)
}

///|
pub(all) struct RecordWriteInput {
  body : WriteBody
  target : RecordTarget?
  trace_id : String
}

///|
/// An immutable protocol candidate. It creates no nominal use, send claim,
/// request-marker property, approval, success or idempotency guarantee.
pub struct RecordBatchRequest {
  priv catalog : PropertyCatalog
  operation : RecordWriteOperation
  priv inputs : Array[RecordWriteInput]
  priv document : @encode.EncodedDocument
  priv marker : RecordRequestMarker?
}

///|
pub fn prepare_record_target(
  catalog : PropertyCatalog,
  key : String,
  bytes : Bytes,
  limits : WriteBodyLimits,
) -> Result[RecordTarget, RecordRequestIssue] {
  if limits.max_input_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_bytes <= 0 ||
    limits.max_value_nodes <= 0 ||
    limits.max_value_text_bytes <= 0 ||
    limits.max_comparison_work <= 0 ||
    limits.max_output_bytes <= 0 ||
    limits.max_output_nodes <= 0 ||
    limits.max_output_depth <= 0 {
    return Err(InvalidLimits)
  }
  if key.length() > limits.max_name_bytes ||
    @utf8.encode(key).length() > limits.max_name_bytes {
    return Err(BudgetExceeded)
  }
  let property : PropertyMetadata = if key == "id" {
    {
      name: "id",
      native_type: "string",
      field_type: "text",
      options: [],
      unique: true,
      writable: Some(false),
    }
  } else {
    match require_unique_property(catalog, key) {
      Ok(_) => ()
      Err(issue) => return Err(Property(issue))
    }
    property_named(catalog, key).unwrap()
  }
  let contract = if key == "id" {
    @contract.primitive(@contract.StringType, nullable=false)
  } else {
    match property_contract(catalog, key) {
      Ok(value) => value
      Err(issue) => return Err(Property(issue))
    }
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_input_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidTarget
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_input_bytes,
      max_total_string_bytes: limits.max_input_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidTarget)
  }
  let value = match
    @admitted.admit(contract, cursor, {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_value_text_bytes,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Value(ValueAdmission(key, issue)))
  }
  match value.value {
    Null | Array(_) | Object(_) => return Err(InvalidTarget)
    _ => ()
  }
  let provider_value = match
    write_property_text(property, value, limits.max_output_bytes) {
    Ok(value) if !value.is_empty() => value
    Ok(_) => return Err(InvalidTarget)
    Err(issue) => return Err(Value(issue))
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @admitted.emit_checked_wire_value(value, writer)
    Ok({ catalog, key, value_wire: @encode.finish(writer), provider_value, })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
/// Emit only complete Encoder-owned property documents. No JSON reparsing,
/// binary64 conversion, unbounded concatenation or caller-supplied raw JSON.
pub fn prepare_record_batch_request(
  catalog : PropertyCatalog,
  operation : RecordWriteOperation,
  inputs : Array[RecordWriteInput],
  limits : RecordRequestLimits,
) -> Result[RecordBatchRequest, RecordRequestIssue] {
  prepare_record_batch_original(catalog, operation, inputs, None, limits)
}

///|
pub fn prepare_marked_record_batch_request(
  catalog : PropertyCatalog,
  operation : RecordWriteOperation,
  inputs : Array[RecordWriteInput],
  marker : RecordRequestMarker,
  limits : RecordRequestLimits,
) -> Result[RecordBatchRequest, RecordRequestIssue] {
  prepare_record_batch_original(
    catalog,
    operation,
    inputs,
    Some(marker),
    limits,
  )
}

///|
fn prepare_record_batch_original(
  catalog : PropertyCatalog,
  operation : RecordWriteOperation,
  inputs : Array[RecordWriteInput],
  marker : RecordRequestMarker?,
  limits : RecordRequestLimits,
) -> Result[RecordBatchRequest, RecordRequestIssue] {
  if limits.max_rows <= 0 ||
    limits.max_rows > 100 ||
    limits.max_properties <= 0 ||
    limits.max_trace_bytes <= 0 ||
    limits.max_body_bytes <= 0 ||
    limits.max_body_nodes <= 0 ||
    limits.max_body_depth <= 0 {
    return Err(InvalidLimits)
  }
  if inputs.is_empty() || inputs.length() > limits.max_rows {
    return Err(BudgetExceeded)
  }
  if marker is Some(original) {
    match
      recheck_property_catalog(original.catalog, catalog, limits.max_properties) {
      Ok(_) => ()
      Err(_) => return Err(ForeignCatalog)
    }
  }
  match operation {
    Upsert(key) => {
      if key == "id" {
        return Err(ForeignTargetKey)
      }
      match require_unique_property(catalog, key) {
        Ok(_) => ()
        Err(issue) => return Err(Property(issue))
      }
    }
    _ => ()
  }
  let targets : Map[String, Bool] = Map([])
  let traces : Map[String, Bool] = Map([])
  for input in inputs {
    if marker is Some(original) &&
      (
        input.body.names.contains(original.property) ||
        (input.target is Some(target) && target.key == original.property)
      ) {
      return Err(MarkerConflict)
    }
    match recheck_write_body(input.body, catalog, limits.max_properties) {
      Ok(_) => ()
      Err(_) => return Err(ForeignCatalog)
    }
    if input.trace_id.is_empty() ||
      input.trace_id.length() > limits.max_trace_bytes ||
      @utf8.encode(input.trace_id).length() > limits.max_trace_bytes {
      return Err(InvalidTrace)
    }
    if traces.contains(input.trace_id) {
      return Err(DuplicateTrace)
    }
    traces[input.trace_id] = true
    match (operation, input.target) {
      (Create, None) => ()
      (Create, Some(_)) => return Err(UnexpectedTarget)
      (_, None) => return Err(MissingTarget)
      (operation, Some(target)) => {
        match
          recheck_property_catalog(
            target.catalog,
            catalog,
            limits.max_properties,
          ) {
          Ok(_) => ()
          Err(_) => return Err(ForeignCatalog)
        }
        let key = match operation {
          Update => "id"
          Upsert(key) => key
          Create => return Err(UnexpectedTarget)
        }
        if target.key != key {
          return Err(ForeignTargetKey)
        }
        if targets.contains(target.value_wire) {
          return Err(DuplicateTarget)
        }
        targets[target.value_wire] = true
      }
    }
  }
  let writer = @encode.writer(
    limits.max_body_bytes,
    limits.max_body_nodes,
    limits.max_body_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "inputs")
    @encode.begin_array(writer)
    for input in inputs {
      @encode.begin_object(writer)
      match input.target {
        Some(target) => {
          @encode.key(writer, "id")
          @encode.string_value(writer, target.provider_value)
          match operation {
            Upsert(key) => {
              @encode.key(writer, "idProperty")
              @encode.string_value(writer, key)
            }
            _ => ()
          }
        }
        None => ()
      }
      @encode.key(writer, "objectWriteTraceId")
      @encode.string_value(writer, input.trace_id)
      @encode.key(writer, "properties")
      match marker {
        None => @encode.emit_document(writer, input.body.properties_document)
        Some(original) =>
          emit_marked_record_properties(writer, input.body, original, limits)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok({
      catalog,
      operation,
      inputs: inputs.copy(),
      document: @encode.finish_document(writer),
      marker,
    })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn record_batch_request_body(request : RecordBatchRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn record_batch_request_object_type(request : RecordBatchRequest) -> String {
  request.catalog.object_type
}

///|
pub fn record_batch_request_count(request : RecordBatchRequest) -> Int {
  request.inputs.length()
}

///|
pub fn record_batch_request_input(
  request : RecordBatchRequest,
  index : Int,
) -> RecordWriteInput? {
  if index < 0 || index >= request.inputs.length() {
    None
  } else {
    Some(request.inputs[index])
  }
}

///|
pub fn recheck_record_batch_request(
  request : RecordBatchRequest,
  current : PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, PropertyIssue] {
  recheck_property_catalog(request.catalog, current, max_properties)
}
