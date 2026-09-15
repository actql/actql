///|
/// Complete checked Relation schemas only. This is not a constructor for an
/// open shape with unknown field types. Both schemas retain their kernel owner.
priv struct OrderedShapes {
  params : OrderedParams
  input : @schema.Schema
  output : @schema.Schema
  input_cid : String
  output_cid : String
}

///|
pub(all) enum OrderedShapeIssue {
  InvalidLimits
  ShapeLimit
  InvalidPrefix
}

///|
fn emit_closed_row_shape(
  schema : @schema.Schema,
  out : @encode.Writer,
  self_cid? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "additional_fields")
  @encode.bool_value(out, false)
  @encode.key(out, "fields")
  @encode.begin_object(out)
  for i = 0; i < @schema.field_count(schema); i = i + 1 {
    let field = @schema.field_at(schema, i).unwrap()
    @encode.key(out, @schema.reference_name(field.name))
    @contract.emit_checked(field.contract, out)
  }
  @encode.end_object(out)
  @encode.key(out, "required_fields")
  @encode.begin_array(out)
  for i = 0; i < @schema.field_count(schema); i = i + 1 {
    @encode.string_value(
      out,
      @schema.reference_name(@schema.field_at(schema, i).unwrap().name),
    )
  }
  @encode.end_array(out)
  match self_cid {
    Some(cid) => {
      @encode.key(out, "self_cid")
      @encode.string_value(out, cid)
    }
    None => ()
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-derive-row-shape/0.1")
  @encode.end_object(out)
}

///|
fn prepare_ordered_shapes(
  params : OrderedParams,
  limits : RegistryLimits,
) -> Result[OrderedShapes, OrderedShapeIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 0 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let kernel = ordered_params_kernel(params)
  let input = @lower.kernel_input_schema(kernel)
  let output = @lower.kernel_output_schema(kernel)
  let ids = try {
    let before = @encode.hashing_writer(
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    emit_closed_row_shape(input, before)
    let after = @encode.hashing_writer(
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    emit_closed_row_shape(output, after)
    (
      "sha256:" + @encode.finish_hash(before),
      "sha256:" + @encode.finish_hash(after),
    )
  } catch {
    _ => return Err(ShapeLimit)
  }
  Ok({ params, input, output, input_cid: ids.0, output_cid: ids.1, })
}

///|
/// Prefix comes from checked bindings, never from a caller-supplied slot table.
/// Emits the self-CID preimage; the envelope will add self_cid separately.
fn emit_ordered_context(
  shapes : OrderedShapes,
  prefix : Int,
  out : @encode.Writer,
  self_cid? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  if prefix < 0 ||
    prefix > @lower.ordered_binding_count(ordered_params_kernel(shapes.params)) {
    raise @encode.InvalidStructure
  }
  @encode.begin_object(out)
  @encode.key(out, "input_contract_cid")
  @encode.string_value(out, shapes.input_cid)
  @encode.key(out, "prior_slots")
  @encode.begin_array(out)
  for i = 0; i < prefix; i = i + 1 {
    guard @lower.ordered_binding_at(ordered_params_kernel(shapes.params), i)
      is Some((name, expression)) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "contract")
    @contract.emit_checked(@lower.expression_contract(expression), out)
    @encode.key(out, "name")
    @encode.string_value(out, name)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  match self_cid {
    Some(cid) => {
      @encode.key(out, "self_cid")
      @encode.string_value(out, cid)
    }
    None => ()
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-derive-row-context/0.1")
  @encode.end_object(out)
}
