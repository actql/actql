///|
/// Complete AoA step shape for the existing Relation operations. An individual
/// emitted step is not a pipeline, contract-admission proof or execution permit.
pub fn emit_kernel_node(
  kernel : PreparedKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  // Ordered params require their complete occurrence table and evidence path.
  // Preparation alone must not emit an executable-looking alternative.
  if kernel.body is OrderedBindings(_) {
    raise @encode.InvalidStructure
  }
  let node = kernel.owner.prepared.nodes[kernel.step_index]
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, kernel.input_id)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(
    out,
    match kernel.body {
      SnapshotMap(_) => "REL.derive"
      Filter(_) => "REL.where"
      Select(_) => "REL.select"
      Limit(_, _, _) => "REL.limit"
      OrderedBindings(_) => raise @encode.InvalidStructure
    },
  )
  @encode.key(out, "params")
  @encode.begin_object(out)
  match kernel.body {
    OrderedBindings(_) => raise @encode.InvalidStructure
    SnapshotMap(bindings) => {
      @encode.key(out, "exprs")
      @encode.begin_object(out)
      for (name, expr) in bindings {
        @encode.key(out, name)
        emit_expression(expr, out)
      }
      @encode.end_object(out)
    }
    Filter(expr) => {
      @encode.key(out, "expr")
      emit_expression(expr, out)
    }
    Limit(count, offset, _) => {
      @encode.key(out, "count")
      @encode.number_value(out, count.to_double())
      @encode.key(out, "offset")
      @encode.number_value(out, offset.to_double())
    }
    Select(fields) => {
      @encode.key(out, "columns")
      @encode.begin_array(out)
      for field in fields {
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
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
