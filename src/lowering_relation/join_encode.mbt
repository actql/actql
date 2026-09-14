///|
fn emit_join_column(
  out : @encode.Writer,
  side : String,
  field : @schema.FieldName,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "path")
  @encode.begin_array(out)
  @encode.string_value(out, side)
  @encode.string_value(out, @schema.reference_name(field))
  @encode.end_array(out)
  @encode.key(out, "type")
  @encode.string_value(out, "col")
  @encode.end_object(out)
}

///|
/// Join followed by the checked canonical projection. No key occurrence or
/// projection alias is deduplicated, and no expression-demand slot is invented.
pub fn emit_join_kernel(
  kernel : PreparedJoinKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = kernel.owner.prepared.nodes[kernel.step]
  let profile = kernel.profile
  let checked = profile.checked
  let raw = node.projection_id.unwrap()
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, raw)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.join")
  @encode.key(out, "params")
  @encode.begin_object(out)
  if @join.assertion(checked) is Some(cardinality) {
    @encode.key(out, "cardinality")
    @encode.string_value(
      out,
      match cardinality {
        OneToOne => "one_to_one"
        ManyToOne => "many_to_one"
        OneToMany => "one_to_many"
      },
    )
  }
  @encode.key(out, "how")
  @encode.string_value(out, "inner")
  @encode.key(out, "key_pairs")
  @encode.begin_array(out)
  for (left, right) in profile.keys {
    @encode.begin_object(out)
    @encode.key(out, "left")
    @encode.string_value(out, @schema.reference_name(left))
    @encode.key(out, "right")
    @encode.string_value(out, @schema.reference_name(right))
    @encode.end_object(out)
  }
  @encode.end_array(out)
  if kernel.output_limit is Some(limit) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, limit.to_double())
  }
  @encode.key(out, "null_key")
  @encode.string_value(
    out,
    if @join.null_key(checked) == Fail {
      "fail"
    } else {
      "no_match"
    },
  )
  @encode.key(out, "on")
  if profile.keys.length() > 1 {
    @encode.begin_object(out)
    @encode.key(out, "args")
    @encode.begin_array(out)
  }
  for (left, right) in profile.keys {
    @encode.begin_object(out)
    @encode.key(out, "left")
    emit_join_column(out, "left", left)
    @encode.key(out, "op")
    @encode.string_value(out, "eq")
    @encode.key(out, "right")
    emit_join_column(out, "right", right)
    @encode.key(out, "type")
    @encode.string_value(out, "cmp")
    @encode.end_object(out)
  }
  if profile.keys.length() > 1 {
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "and")
    @encode.key(out, "type")
    @encode.string_value(out, "bool")
    @encode.end_object(out)
  }
  @encode.key(out, "on_duplicate")
  @encode.string_value(out, "fail")
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, raw)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.select")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for field in profile.projection {
    if field.input == field.output {
      @encode.string_value(out, @schema.reference_name(field.input))
    } else {
      @encode.begin_object(out)
      @encode.key(out, "from")
      @encode.string_value(out, @schema.reference_name(field.input))
      @encode.key(out, "to")
      @encode.string_value(out, @schema.reference_name(field.output))
      @encode.end_object(out)
    }
  }
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
