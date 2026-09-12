///|
/// Owned request for the existing per-kernel Relation binding. Not fragment
/// admission: graph, roots, resource witnesses and backend checks remain.
struct FragmentRequest {
  pipeline : FragmentPipeline
  max_rows : Int64
  max_value_bytes : Int64
}

///|
/// Declared request ceilings from this owner, not inferred cardinalities.
pub fn fragment_request_ceilings(request : FragmentRequest) -> (Int64, Int64) {
  (request.max_rows, request.max_value_bytes)
}

///|
pub(all) enum FragmentRequestIssue {
  InvalidRequestCeiling
}

///|
pub fn prepare_fragment_request(
  pipeline : FragmentPipeline,
  max_rows : Int64,
  max_value_bytes : Int64,
) -> Result[FragmentRequest, FragmentRequestIssue] {
  if max_rows < 1L ||
    max_rows > 9007199254740991L ||
    max_value_bytes < 1L ||
    max_value_bytes > 9007199254740991L {
    return Err(InvalidRequestCeiling)
  }
  Ok({ pipeline, max_rows, max_value_bytes, })
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
    SnapshotMap(bindings) =>
      for (_, expression) in bindings {
        if expression.body is TypedNull {
          has_null = true
        }
      }
    Filter(_) => ()
    OrderedBindings(_) | Select(_) => raise @encode.InvalidStructure
  }
  if has_null {
    @encode.key(out, "null_contexts")
    @encode.begin_object(out)
    @encode.key(out, kernel.owner.prepared.nodes[kernel.step_index].id)
    @encode.begin_object(out)
    match kernel.body {
      SnapshotMap(bindings) =>
        for (name, expression) in bindings {
          if expression.body is TypedNull {
            @encode.key(out, name)
            @contract.emit_checked(expression.contract, out)
          }
        }
      Filter(_) | OrderedBindings(_) | Select(_) =>
        raise @encode.InvalidStructure
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
