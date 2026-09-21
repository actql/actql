///|
/// Prepared canonical Graph union. The authored finite input list remains one
/// operation occurrence; this view does not introduce a binary fold tree.
struct PreparedGraphUnion {
  node : PreparedNode
  checked : @graph.CheckedUnion
}

///|
pub fn graph_union_input_count(value : PreparedGraphUnion) -> Int {
  1 + @graph.union_count(value.checked)
}

///|
pub fn graph_union_has_property_strategies(value : PreparedGraphUnion) -> Bool {
  for index in 0..<@graph.union_count(value.checked) {
    guard @graph.union_fold_at(value.checked, index) is Some(fold) else {
      return true
    }
    if @graph.structural_strategy_count(fold, @schema.Left) > 0 ||
      @graph.structural_strategy_count(fold, @schema.Right) > 0 {
      return true
    }
  }
  false
}

///|
fn prepare_graph_union_node(
  node : PreparedNode,
) -> Result[PreparedGraphUnion, SequenceIssue] {
  guard node.payload is GraphUnion(checked) else { return Err(SequenceLimit) }
  Ok({ node, checked, })
}

///|
fn emit_structural_strategy(
  strategy : @graph.FieldStrategy,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(
    out,
    match strategy {
      @graph.ExactEqual => "exact_equal"
      @graph.SetUnion => "set_union"
      @graph.SetDifference => "set_difference"
      @graph.NumberSum => "number_sum"
      @graph.NumberMean => "number_mean"
      @graph.NumberMin => "number_min"
      @graph.NumberMax => "number_max"
    },
  )
}

///|
fn emit_structural_strategy_map(
  checked : @graph.CheckedStructural,
  side : @schema.Side,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  for index in 0..<@graph.structural_strategy_count(checked, side) {
    let strategy = @graph.structural_strategy_at(checked, side, index).unwrap()
    @encode.key(out, @graph.property_strategy_name(strategy))
    emit_structural_strategy(@graph.property_strategy_kind(strategy), out)
  }
  @encode.end_object(out)
}

///|
fn emit_graph_union_params(
  checked : @graph.CheckedUnion,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let fold = @graph.union_fold_at(checked, 0).unwrap()
  emit_checked_structural_params(fold, out)
}

///|
fn emit_checked_structural_params(
  fold : @graph.CheckedStructural,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node_count = @graph.structural_strategy_count(fold, @schema.Left)
  let edge_count = @graph.structural_strategy_count(fold, @schema.Right)
  @encode.begin_object(out)
  if node_count > 0 || edge_count > 0 {
    @encode.key(out, "merge")
    @encode.begin_object(out)
    if edge_count > 0 {
      @encode.key(out, "edge_properties")
      emit_structural_strategy_map(fold, @schema.Right, out)
    }
    if node_count > 0 {
      @encode.key(out, "node_properties")
      emit_structural_strategy_map(fold, @schema.Left, out)
    }
    @encode.end_object(out)
  }
  @encode.end_object(out)
}

///|
struct PreparedGraphStructural {
  node : PreparedNode
  checked : @graph.CheckedStructural
}

///|
pub fn graph_structural_has_property_strategies(
  value : PreparedGraphStructural,
) -> Bool {
  @graph.structural_strategy_count(value.checked, @schema.Left) > 0 ||
  @graph.structural_strategy_count(value.checked, @schema.Right) > 0
}

///|
fn prepare_graph_structural_node(
  node : PreparedNode,
) -> Result[PreparedGraphStructural, SequenceIssue] {
  guard node.payload is StructuralGraph(checked) else {
    return Err(SequenceLimit)
  }
  Ok({ node, checked, })
}

///|
fn emit_graph_structural_node(
  prepared : PreparedGraphStructural,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  emit_checked_structural_params(prepared.checked, out)
  @encode.end_object(out)
}

///|
fn emit_graph_union_node(
  prepared : PreparedGraphUnion,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "SGA.union_structural")
  @encode.key(out, "params")
  emit_graph_union_params(prepared.checked, out)
  @encode.end_object(out)
}
