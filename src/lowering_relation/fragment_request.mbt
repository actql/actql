///|
/// Owned request for the existing per-kernel Relation binding. Not fragment
/// admission: graph, roots, resource witnesses and backend checks remain.
struct FragmentRequest {
  pipeline : FragmentPipeline
  max_rows : Int64
  max_value_bytes : Int64
  row_limits : FragmentRowLimits?
}

///|
/// Declared request ceilings from this owner, not inferred cardinalities.
pub fn fragment_request_ceilings(request : FragmentRequest) -> (Int64, Int64) {
  (request.max_rows, request.max_value_bytes)
}

///|
pub fn fragment_request_pipeline(request : FragmentRequest) -> FragmentPipeline {
  request.pipeline
}

///|
pub fn fragment_request_row_limits(
  request : FragmentRequest,
) -> FragmentRowLimits? {
  request.row_limits
}

///|
pub(all) enum FragmentRequestIssue {
  InvalidRequestCeiling
  InvalidRowLimits
  RowLimitsMismatch
}

///|
pub fn prepare_fragment_request(
  pipeline : FragmentPipeline,
  max_rows : Int64,
  max_value_bytes : Int64,
  row_limits? : FragmentRowLimits? = None,
) -> Result[FragmentRequest, FragmentRequestIssue] {
  if max_rows < 1L ||
    max_rows > 9007199254740991L ||
    max_value_bytes < 1L ||
    max_value_bytes > 9007199254740991L {
    return Err(InvalidRequestCeiling)
  }
  match (pipeline.kernel.body, row_limits) {
    (OrderedBindings(_), Some(limits)) => {
      if !fragment_row_limits_valid(limits) {
        return Err(InvalidRowLimits)
      }
      if limits.max_input_rows > max_rows ||
        limits.max_value_bytes > max_value_bytes {
        return Err(InvalidRequestCeiling)
      }
    }
    (OrderedBindings(_), None) => return Err(RowLimitsMismatch)
    (_, Some(_)) => return Err(RowLimitsMismatch)
    (_, None) => ()
  }
  Ok({ pipeline, max_rows, max_value_bytes, row_limits, })
}

///|
/// Value projection using shared codecs, not canonical byte serialization.
/// Parameters come only from this kernel's already owner-checked bindings.
pub fn emit_fragment_request(
  request : FragmentRequest,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let kernel = request.pipeline.kernel
  @encode.begin_object(out)
  @encode.key(out, "max_rows")
  @encode.number_value(out, request.max_rows.to_double())
  @encode.key(out, "max_value_bytes")
  @encode.number_value(out, request.max_value_bytes.to_double())
  // A typed-null root already carries the checker's contextual type. Do not
  // derive a context from later operations or reinterpret literal data.
  let mut has_null = false
  match kernel.body {
    SnapshotMap(bindings) | OrderedBindings(bindings) =>
      for (_, expression) in bindings {
        if is_contextual_null_root(expression) {
          has_null = true
        }
      }
    Filter(_) | AssertAll(_) | Groups(_) | AnalyticRows(_) => ()
    Select(_)
    | AssertUnique(_)
    | JsonPick(_, _, _)
    | Limit(_, _, _)
    | TopK(_, _)
    | PartitionedTopK(_, _)
    | Pivot(_)
    | Unnest(_, _, _, _, _)
    | Unpivot(_, _, _, _)
    | DistinctRows
    | DedupeRows
    | StableSort(_)
    | Lag(_, _)
    | Watermark(_, _, _, _)
    | CountGroups(_) => raise @encode.InvalidStructure
  }
  if has_null {
    @encode.key(out, "null_contexts")
    @encode.begin_object(out)
    @encode.key(out, kernel.owner.prepared.nodes[kernel.step_index].id)
    @encode.begin_object(out)
    match kernel.body {
      SnapshotMap(bindings) | OrderedBindings(bindings) =>
        for (name, expression) in bindings {
          if is_contextual_null_root(expression) {
            @encode.key(out, name)
            @contract.emit_checked(expression.contract, out)
          }
        }
      Filter(_)
      | AssertAll(_)
      | AssertUnique(_)
      | JsonPick(_, _, _)
      | Select(_)
      | Limit(_, _, _)
      | TopK(_, _)
      | PartitionedTopK(_, _)
      | Pivot(_)
      | Unnest(_, _, _, _, _)
      | Unpivot(_, _, _, _)
      | DistinctRows
      | DedupeRows
      | StableSort(_)
      | Lag(_, _)
      | Watermark(_, _, _, _)
      | CountGroups(_)
      | AnalyticRows(_)
      | Groups(_) => raise @encode.InvalidStructure
    }
    @encode.end_object(out)
    @encode.end_object(out)
  }
  @encode.key(out, "parameters")
  @encode.begin_object(out)
  match kernel.owner.bindings {
    None => ()
    Some(bound) =>
      for i = 0; i < @parameter.bound_value_count(bound); i = i + 1 {
        let parameter = @parameter.bound_value_at(bound, i).unwrap()
        @encode.key(out, parameter.name)
        @encode.begin_object(out)
        @encode.key(out, "contract")
        @contract.emit_checked(parameter.value.contract, out)
        @encode.key(out, "value")
        emit_wire_value(parameter.value.value, out)
        @encode.end_object(out)
      }
  }
  @encode.end_object(out)
  @encode.key(out, "pipeline")
  emit_fragment_source_pipeline(request.pipeline, out)
  if request.row_limits is Some(limits) {
    let hashing = @encode.hashing_writer(1024, 16, 2)
    emit_fragment_row_limits_body(limits, None, hashing)
    let cid = "sha256:" + @encode.finish_hash(hashing)
    @encode.key(out, "row_kernel_limits")
    @encode.begin_object(out)
    @encode.key(out, kernel.owner.prepared.nodes[kernel.step_index].id)
    emit_fragment_row_limits_body(limits, Some(cid), out)
    @encode.end_object(out)
  }
  @encode.key(out, "source_schemas")
  @encode.begin_object(out)
  @encode.key(out, "input")
  @encode.begin_object(out)
  let schema = @relation.input_schema(kernel.checked)
  for i = 0; i < @schema.field_count(schema); i = i + 1 {
    let field = @schema.field_at(schema, i).unwrap()
    @encode.key(out, @schema.reference_name(field.name))
    @contract.emit_checked(field.contract, out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}

///|
/// A NULL parameter gets its type from the parameter declaration, not from
/// request.null_contexts. Only an authored literal root needs that context.
fn is_contextual_null_root(expression : Expression) -> Bool {
  expression.body is TypedNull &&
  @typing.node_form(expression.typed_owner, 0)
  is Some(@typing.Expression("literal", _))
}
