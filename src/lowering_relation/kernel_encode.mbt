///|
/// Complete AoA step shape for the existing Relation operations. An individual
/// emitted step is not a pipeline, contract-admission proof or execution permit.
pub fn emit_kernel_node(
  kernel : PreparedKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let group_keys = match kernel.body {
    CountGroups(group) => Some(group.keys)
    Groups(group) if !group.window => Some(group.keys)
    _ => None
  }
  if group_keys is Some(keys) {
    let node = kernel.owner.prepared.nodes[kernel.step_index]
    guard node.aggregation_id is Some(input) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "id")
    @encode.string_value(out, node.id)
    @encode.key(out, "in")
    @encode.begin_array(out)
    @encode.string_value(out, input)
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "REL.orderByStable")
    @encode.key(out, "params")
    @encode.begin_object(out)
    @encode.key(out, "by")
    @encode.begin_array(out)
    for field in keys {
      @encode.begin_object(out)
      @encode.key(out, "dir")
      @encode.string_value(out, "asc")
      @encode.key(out, "field")
      @encode.string_value(out, @schema.reference_name(field))
      @encode.key(out, "nulls")
      @encode.string_value(out, "first")
      @encode.end_object(out)
    }
    @encode.end_array(out)
    @encode.end_object(out)
    @encode.end_object(out)
    return
  }
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
  @encode.string_value(
    out,
    node.order_id.unwrap_or(node.projection_id.unwrap_or(kernel.input_id)),
  )
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(
    out,
    match kernel.body {
      SnapshotMap(_) => "REL.derive"
      Filter(_) => "REL.where"
      AssertAll(_) => "REL.assert_all"
      AssertUnique(_) => "REL.assert_unique"
      JsonPick(_, _, _) => "REL.json.pick"
      Select(_) => "REL.select"
      Limit(_, _, _) => "REL.limit"
      TopK(_, _) => "REL.topk"
      PartitionedTopK(_, _) => "REL.topk_partitioned"
      Pivot(_) => "REL.pivot"
      Unnest(_, _, _, _, _) => "REL.unnest"
      Unpivot(_, _, _, _) => "REL.unpivot"
      DistinctRows => "REL.distinct"
      DedupeRows => "REL.dedupeRows"
      StableSort(_) => "REL.orderByStable"
      CountGroups(_) => "REL.groupBy"
      Groups(group) =>
        if group.window {
          "REL.window.project"
        } else {
          "REL.groupBy"
        }
      OrderedBindings(_) => raise @encode.InvalidStructure
    },
  )
  @encode.key(out, "params")
  if kernel.body is Groups(group) && group.window {
    emit_group_params(group, out)
    @encode.end_object(out)
    return
  }
  @encode.begin_object(out)
  match kernel.body {
    CountGroups(_) | Groups(_) => raise @encode.InvalidStructure
    DistinctRows => ()
    StableSort(_) => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for i = 0; i < kernel_sort_term_count(kernel); i = i + 1 {
        let (field, descending, nulls_first) = kernel_sort_term_at(kernel, i).unwrap()
        @encode.begin_object(out)
        @encode.key(out, "dir")
        @encode.string_value(out, if descending { "desc" } else { "asc" })
        @encode.key(out, "field")
        @encode.string_value(out, @schema.reference_name(field))
        @encode.key(out, "nulls")
        @encode.string_value(out, if nulls_first { "first" } else { "last" })
        @encode.end_object(out)
      }
      @encode.end_array(out)
    }
    TopK(count, _) | PartitionedTopK(count, _) => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for i = 0; i < kernel_sort_term_count(kernel); i = i + 1 {
        let (field, descending, nulls_first) = kernel_sort_term_at(kernel, i).unwrap()
        @encode.begin_object(out)
        @encode.key(out, "dir")
        @encode.string_value(out, if descending { "desc" } else { "asc" })
        @encode.key(out, "field")
        @encode.string_value(out, @schema.reference_name(field))
        @encode.key(out, "nulls")
        @encode.string_value(out, if nulls_first { "first" } else { "last" })
        @encode.end_object(out)
      }
      @encode.end_array(out)
      @encode.key(out, "k")
      @encode.number_value(out, count.to_double())
      if kernel.body is PartitionedTopK(_, _) {
        @encode.key(out, "partition_by")
        @encode.begin_array(out)
        for i = 0; i < kernel_top_k_partition_count(kernel); i = i + 1 {
          @encode.string_value(
            out,
            @schema.reference_name(
              kernel_top_k_partition_at(kernel, i).unwrap(),
            ),
          )
        }
        @encode.end_array(out)
      }
    }
    Pivot(pivot) => {
      @encode.key(out, "aggregate")
      @encode.string_value(
        out,
        match pivot_function(pivot) {
          @relation.Sum => "sum"
          @relation.Avg => "avg"
          @relation.Count => "count"
          @relation.Min => "min"
          @relation.Max => "max"
          @relation.First => "first"
          _ => raise @encode.InvalidStructure
        },
      )
      if pivot_fill(pivot) is Some(fill) {
        @encode.key(out, "fill")
        match fill {
          Null => @encode.null_value(out)
          Value(value) => emit_wire_value(value.value, out)
        }
      }
      @encode.key(out, "index")
      @encode.begin_array(out)
      for i = 0; i < pivot_index_count(pivot); i = i + 1 {
        @encode.string_value(
          out,
          @schema.reference_name(pivot_index_at(pivot, i).unwrap()),
        )
      }
      @encode.end_array(out)
      @encode.key(out, "pivot")
      @encode.string_value(out, @schema.reference_name(pivot_column(pivot)))
      @encode.key(out, "value")
      @encode.string_value(out, @schema.reference_name(pivot_value(pivot)))
      @encode.key(out, "values")
      @encode.begin_array(out)
      for i = 0; i < pivot_axis_count(pivot); i = i + 1 {
        @encode.string_value(out, pivot_axis_at(pivot, i).unwrap())
      }
      @encode.end_array(out)
    }
    Unnest(column, element, index, outer, _) => {
      @encode.key(out, "as")
      @encode.string_value(out, element)
      @encode.key(out, "column")
      @encode.string_value(out, @schema.reference_name(column))
      @encode.key(out, "outer")
      @encode.bool_value(out, outer)
      if index is Some(name) {
        @encode.key(out, "with_index")
        @encode.string_value(out, name)
      }
    }
    Unpivot(columns, keep, name_column, value_column) => {
      @encode.key(out, "columns")
      @encode.begin_array(out)
      for field in columns {
        @encode.string_value(out, @schema.reference_name(field))
      }
      @encode.end_array(out)
      @encode.key(out, "keep")
      @encode.begin_array(out)
      for field in keep {
        @encode.string_value(out, @schema.reference_name(field))
      }
      @encode.end_array(out)
      @encode.key(out, "name_column")
      @encode.string_value(out, name_column)
      @encode.key(out, "value_column")
      @encode.string_value(out, value_column)
    }
    DedupeRows => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for i = 0; i < kernel_dedupe_key_count(kernel); i = i + 1 {
        @encode.string_value(
          out,
          @schema.reference_name(kernel_dedupe_key_at(kernel, i).unwrap()),
        )
      }
      @encode.end_array(out)
      @encode.key(out, "keep")
      @encode.string_value(out, "first")
      @encode.key(out, "on_tie")
      @encode.string_value(out, "fail")
      @encode.key(out, "order_by")
      @encode.begin_array(out)
      for i = 0; i < kernel_dedupe_order_count(kernel); i = i + 1 {
        let (field, descending, nulls_first) = kernel_dedupe_order_at(kernel, i).unwrap()
        @encode.begin_object(out)
        @encode.key(out, "dir")
        @encode.string_value(out, if descending { "desc" } else { "asc" })
        @encode.key(out, "field")
        @encode.string_value(out, @schema.reference_name(field))
        @encode.key(out, "nulls")
        @encode.string_value(out, if nulls_first { "first" } else { "last" })
        @encode.end_object(out)
      }
      @encode.end_array(out)
    }
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
    AssertAll(expr) => {
      @encode.key(out, "expr")
      emit_expression(expr, out)
    }
    AssertUnique(keys) => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for field in keys {
        @encode.string_value(out, @schema.reference_name(field))
      }
      @encode.end_array(out)
    }
    JsonPick(column, path, output) => {
      @encode.key(out, "column")
      @encode.string_value(out, @schema.reference_name(column))
      @encode.key(out, "output")
      @encode.string_value(out, output)
      @encode.key(out, "path")
      @encode.begin_array(out)
      for name in path {
        @encode.string_value(out, name)
      }
      @encode.end_array(out)
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

///|
/// Canonical keyed-distinct expansion, not a physical optimization or an alias.
fn emit_kernel_prefix(
  kernel : PreparedKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = kernel.owner.prepared.nodes[kernel.step_index]
  if kernel.body is CountGroups(group) {
    guard node.aggregation_id is Some(id) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "id")
    @encode.string_value(out, id)
    @encode.key(out, "in")
    @encode.begin_array(out)
    @encode.string_value(out, kernel.input_id)
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "REL.groupBy")
    @encode.key(out, "params")
    emit_count_group_params(group, out)
    @encode.end_object(out)
    return
  }
  if kernel.body is Groups(group) && !group.window {
    guard node.aggregation_id is Some(id) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "id")
    @encode.string_value(out, id)
    @encode.key(out, "in")
    @encode.begin_array(out)
    @encode.string_value(out, kernel.input_id)
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "REL.groupBy")
    @encode.key(out, "params")
    emit_group_params(group, out)
    @encode.end_object(out)
    return
  }
  if node.order_id is Some(id) {
    @encode.begin_object(out)
    @encode.key(out, "id")
    @encode.string_value(out, id)
    @encode.key(out, "in")
    @encode.begin_array(out)
    @encode.string_value(out, kernel.input_id)
    @encode.end_array(out)
    @encode.key(out, "op")
    @encode.string_value(out, "REL.orderByStable")
    @encode.key(out, "params")
    @encode.begin_object(out)
    @encode.key(out, "by")
    @encode.begin_array(out)
    for i = 0; i < kernel_sort_term_count(kernel); i = i + 1 {
      let (field, _, _) = kernel_sort_term_at(kernel, i).unwrap()
      @encode.begin_object(out)
      @encode.key(out, "dir")
      @encode.string_value(out, "asc")
      @encode.key(out, "field")
      @encode.string_value(out, @schema.reference_name(field))
      @encode.key(out, "nulls")
      @encode.string_value(out, "last")
      @encode.end_object(out)
    }
    @encode.end_array(out)
    @encode.end_object(out)
    @encode.end_object(out)
    return
  }
  guard node.projection_id is Some(id) else { return }
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, kernel.input_id)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.select")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for field in projection_fields(kernel_distinct_projection(kernel).unwrap()) {
    @encode.string_value(out, @schema.reference_name(field.input))
  }
  @encode.end_array(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
