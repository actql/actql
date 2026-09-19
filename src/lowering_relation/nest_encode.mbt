///|
fn nest_generated_id(kernel : PreparedNestKernel, role : String) -> String {
  nest_generated_role_id(kernel.step, role)
}

///|
fn nest_reference_name(
  references : Array[PreparedNestReference],
  field : @schema.FieldName,
) -> String {
  for reference in references {
    if reference.field == field {
      return reference.projected_name
    }
  }
  @schema.reference_name(field)
}

///|
fn emit_nest_column(
  out : @encode.Writer,
  first : String,
  second? : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "path")
  @encode.begin_array(out)
  @encode.string_value(out, first)
  if second is Some(value) {
    @encode.string_value(out, value)
  }
  @encode.end_array(out)
  @encode.key(out, "type")
  @encode.string_value(out, "col")
  @encode.end_object(out)
}

///|
fn emit_nest_literal(
  out : @encode.Writer,
  value : Int,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "type")
  @encode.string_value(out, "lit")
  @encode.key(out, "value")
  @encode.number_value(out, value.to_double())
  @encode.end_object(out)
}

///|
fn emit_nest_equality(
  out : @encode.Writer,
  left_first : String,
  left_second : String?,
  right_first : String,
  right_second : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "left")
  emit_nest_column(out, left_first, second?=left_second)
  @encode.key(out, "op")
  @encode.string_value(out, "eq")
  @encode.key(out, "right")
  emit_nest_column(out, right_first, second?=right_second)
  @encode.key(out, "type")
  @encode.string_value(out, "cmp")
  @encode.end_object(out)
}

///|
fn emit_nest_constant_equality(
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "left")
  emit_nest_literal(out, 1)
  @encode.key(out, "op")
  @encode.string_value(out, "eq")
  @encode.key(out, "right")
  emit_nest_literal(out, 1)
  @encode.key(out, "type")
  @encode.string_value(out, "cmp")
  @encode.end_object(out)
}

///|
fn emit_nest_join_on(
  kernel : PreparedNestKernel,
  reverse : Bool,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if kernel.keys.length() > 1 {
    @encode.begin_object(out)
    @encode.key(out, "args")
    @encode.begin_array(out)
  }
  for key in kernel.keys {
    let left = if reverse {
      nest_reference_name(kernel.child_references, key.right)
    } else {
      nest_reference_name(kernel.parent_references, key.left)
    }
    let right = if reverse {
      nest_reference_name(kernel.parent_references, key.left)
    } else {
      nest_reference_name(kernel.child_references, key.right)
    }
    emit_nest_equality(out, "left", Some(left), "right", Some(right))
  }
  if kernel.keys.length() > 1 {
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "and")
    @encode.key(out, "type")
    @encode.string_value(out, "bool")
    @encode.end_object(out)
  }
}

///|
fn begin_nest_node(
  out : @encode.Writer,
  id : String,
  inputs : Array[String],
  operation : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation)
  @encode.key(out, "params")
}

///|
fn emit_nest_reference_projection(
  kernel : PreparedNestKernel,
  input : String,
  references : Array[PreparedNestReference],
  role : String,
  out : @encode.Writer,
) -> String raise @encode.EncodeFailure {
  if references.is_empty() {
    return input
  }
  let id = nest_generated_id(kernel, role)
  begin_nest_node(out, id, [input], "REL.derive")
  @encode.begin_object(out)
  @encode.key(out, "exprs")
  @encode.begin_object(out)
  let ordered = references.copy()
  ordered.sort_by((left, right) => {
    @canonical.compare_utf16(left.projected_name, right.projected_name)
  })
  for reference in ordered {
    @encode.key(out, reference.projected_name)
    emit_nest_column(
      out,
      @schema.reference_name(reference.field),
      second=reference.identity_field,
    )
  }
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
  id
}

///|
fn emit_nest_aggregate(
  kernel : PreparedNestKernel,
  out : @encode.Writer,
  empty : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "aggs")
  @encode.begin_object(out)
  @encode.key(
    out,
    if empty {
      "__actql_nest_empty"
    } else {
      "__actql_nest_items"
    },
  )
  @encode.begin_object(out)
  @encode.key(out, "expr")
  @encode.begin_object(out)
  @encode.key(out, "fields")
  @encode.begin_object(out)
  let fields = kernel.fields.copy()
  fields.sort_by((left, right) => {
    @canonical.compare_utf16(left.output, right.output)
  })
  for field in fields {
    @encode.key(out, field.output)
    emit_nest_column(out, @schema.reference_name(field.input))
  }
  @encode.end_object(out)
  @encode.key(out, "type")
  @encode.string_value(out, "object")
  @encode.end_object(out)
  @encode.key(out, "fn")
  @encode.string_value(out, "array_agg")
  if empty {
    @encode.key(out, "max_items")
    @encode.number_value(out, 1.0)
  } else if kernel.item_limit is Some(maximum) {
    @encode.key(out, "max_items")
    @encode.number_value(out, maximum.to_double())
  }
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.key(out, "by")
  @encode.begin_array(out)
  if !empty {
    let names : Array[String] = []
    for key in kernel.keys {
      let name = nest_reference_name(kernel.child_references, key.right)
      if !names.contains(name) {
        names.push(name)
        @encode.string_value(out, name)
      }
    }
  }
  @encode.end_array(out)
  @encode.end_object(out)
}

///|
fn emit_nest_parent_columns(
  schema : @schema.Schema,
  out : @encode.Writer,
  side? : String,
) -> Unit raise @encode.EncodeFailure {
  for index in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(
      @schema.field_at(schema, index).unwrap().name,
    )
    if side is Some(prefix) {
      @encode.begin_object(out)
      @encode.key(out, "from")
      @encode.string_value(out, prefix + "." + name)
      @encode.key(out, "to")
      @encode.string_value(out, name)
      @encode.end_object(out)
    } else {
      @encode.string_value(out, name)
    }
  }
}

///|
/// Registered canonical expansion of one checked nest occurrence. The Local
/// evaluator may fuse these nodes, but its meaning and limit sites remain this
/// finite graph.
pub fn emit_nest_kernel(
  kernel : PreparedNestKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = kernel.owner.prepared.nodes[kernel.step]
  let parent_schema = @nest.input_schema(kernel.checked, @schema.Left)
  let child_schema = @nest.input_schema(kernel.checked, @schema.Right)
  let parent = emit_nest_reference_projection(
    kernel,
    node.inputs[0],
    kernel.parent_references,
    "parent_refs",
    out,
  )
  let child = emit_nest_reference_projection(
    kernel,
    node.inputs[1],
    kernel.child_references,
    "child_refs",
    out,
  )

  let matched = nest_generated_id(kernel, "matched")
  begin_nest_node(out, matched, [child, parent], "REL.join")
  @encode.begin_object(out)
  @encode.key(out, "how")
  @encode.string_value(out, "semi")
  @encode.key(out, "key_pairs")
  @encode.begin_array(out)
  for key in kernel.keys {
    @encode.begin_object(out)
    @encode.key(out, "left")
    @encode.string_value(
      out,
      nest_reference_name(kernel.child_references, key.right),
    )
    @encode.key(out, "right")
    @encode.string_value(
      out,
      nest_reference_name(kernel.parent_references, key.left),
    )
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "null_key")
  @encode.string_value(out, "no_match")
  @encode.key(out, "on")
  emit_nest_join_on(kernel, true, out)
  @encode.end_object(out)
  @encode.end_object(out)

  let selected = nest_generated_id(kernel, "children")
  begin_nest_node(out, selected, [matched], "REL.select")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for index in 0..<@schema.field_count(child_schema) {
    let name = @schema.reference_name(
      @schema.field_at(child_schema, index).unwrap().name,
    )
    @encode.begin_object(out)
    @encode.key(out, "from")
    @encode.string_value(out, "left." + name)
    @encode.key(out, "to")
    @encode.string_value(out, name)
    @encode.end_object(out)
  }
  for reference in kernel.child_references {
    @encode.begin_object(out)
    @encode.key(out, "from")
    @encode.string_value(out, "left." + reference.projected_name)
    @encode.key(out, "to")
    @encode.string_value(out, reference.projected_name)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)

  let mut ordered = selected
  if nest_expansion_has_role(kernel.expansion, "ordered") {
    ordered = nest_generated_id(kernel, "ordered")
    begin_nest_node(out, ordered, [selected], "REL.orderByStable")
    @encode.begin_object(out)
    @encode.key(out, "by")
    @encode.begin_array(out)
    for term in kernel.order {
      @encode.begin_object(out)
      @encode.key(out, "dir")
      @encode.string_value(out, if term.descending { "desc" } else { "asc" })
      @encode.key(out, "field")
      @encode.string_value(
        out,
        nest_reference_name(kernel.child_references, term.field),
      )
      @encode.key(out, "nulls")
      @encode.string_value(out, if term.nulls_first { "first" } else { "last" })
      @encode.end_object(out)
    }
    @encode.end_array(out)
    @encode.end_object(out)
    @encode.end_object(out)
  }

  let grouped = nest_generated_id(kernel, "grouped")
  begin_nest_node(out, grouped, [ordered], "REL.groupBy")
  emit_nest_aggregate(kernel, out, false)
  @encode.end_object(out)

  let none = nest_generated_id(kernel, "none")
  begin_nest_node(out, none, [node.inputs[1]], "REL.where")
  @encode.begin_object(out)
  @encode.key(out, "expr")
  @encode.begin_object(out)
  @encode.key(out, "left")
  emit_nest_literal(out, 0)
  @encode.key(out, "op")
  @encode.string_value(out, "eq")
  @encode.key(out, "right")
  emit_nest_literal(out, 1)
  @encode.key(out, "type")
  @encode.string_value(out, "cmp")
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)

  let empty = nest_generated_id(kernel, "empty")
  begin_nest_node(out, empty, [none], "REL.groupBy")
  emit_nest_aggregate(kernel, out, true)
  @encode.end_object(out)

  let attached = nest_generated_id(kernel, "attached")
  begin_nest_node(out, attached, [parent, grouped], "REL.join")
  @encode.begin_object(out)
  @encode.key(out, "cardinality")
  @encode.string_value(out, "many_to_one")
  @encode.key(out, "how")
  @encode.string_value(out, "left")
  @encode.key(out, "key_pairs")
  @encode.begin_array(out)
  for key in kernel.keys {
    @encode.begin_object(out)
    @encode.key(out, "left")
    @encode.string_value(
      out,
      nest_reference_name(kernel.parent_references, key.left),
    )
    @encode.key(out, "right")
    @encode.string_value(
      out,
      nest_reference_name(kernel.child_references, key.right),
    )
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "null_key")
  @encode.string_value(out, "no_match")
  @encode.key(out, "on")
  emit_nest_join_on(kernel, false, out)
  @encode.key(out, "on_duplicate")
  @encode.string_value(out, "fail")
  @encode.end_object(out)
  @encode.end_object(out)

  let retained = nest_generated_id(kernel, "parents")
  begin_nest_node(out, retained, [attached], "REL.select")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  emit_nest_parent_columns(parent_schema, out, side="left")
  @encode.begin_object(out)
  @encode.key(out, "from")
  @encode.string_value(out, "right.__actql_nest_items")
  @encode.key(out, "to")
  @encode.string_value(out, "__actql_nest_items")
  @encode.end_object(out)
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)

  let empty_attached = nest_generated_id(kernel, "empty_attached")
  begin_nest_node(out, empty_attached, [retained, empty], "REL.join")
  @encode.begin_object(out)
  @encode.key(out, "how")
  @encode.string_value(out, "left")
  @encode.key(out, "on")
  emit_nest_constant_equality(out)
  @encode.end_object(out)
  @encode.end_object(out)

  let flat = nest_generated_id(kernel, "flat")
  begin_nest_node(out, flat, [empty_attached], "REL.select")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  emit_nest_parent_columns(parent_schema, out, side="left")
  for
    (from, to) in [
      ("left.__actql_nest_items", "__actql_nest_items"),
      ("right.__actql_nest_empty", "__actql_nest_empty"),
    ] {
    @encode.begin_object(out)
    @encode.key(out, "from")
    @encode.string_value(out, from)
    @encode.key(out, "to")
    @encode.string_value(out, to)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)

  let filled = nest_generated_id(kernel, "filled")
  begin_nest_node(out, filled, [flat], "REL.derive")
  @encode.begin_object(out)
  @encode.key(out, "exprs")
  @encode.begin_object(out)
  @encode.key(out, @nest.into(kernel.checked))
  @encode.begin_object(out)
  @encode.key(out, "else")
  emit_nest_column(out, "__actql_nest_items")
  @encode.key(out, "type")
  @encode.string_value(out, "case")
  @encode.key(out, "when")
  @encode.begin_array(out)
  @encode.begin_object(out)
  @encode.key(out, "cond")
  @encode.begin_object(out)
  @encode.key(out, "expr")
  emit_nest_column(out, "__actql_nest_items")
  @encode.key(out, "type")
  @encode.string_value(out, "isnull")
  @encode.end_object(out)
  @encode.key(out, "then")
  emit_nest_column(out, "__actql_nest_empty")
  @encode.end_object(out)
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)

  begin_nest_node(out, node.id, [filled], "REL.select")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  emit_nest_parent_columns(parent_schema, out)
  @encode.string_value(out, @nest.into(kernel.checked))
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
