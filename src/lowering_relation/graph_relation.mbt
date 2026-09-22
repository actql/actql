///|
struct PreparedGraphRelation {
  node : PreparedNode
  params : PreparedGraphRelationParams
}

///|
pub(all) enum GraphRelationKind {
  GraphsEqualRelation
  GraphDiffRelation
  ApplyGraphRelation
} derive(Eq, Debug)

///|
pub fn graph_relation_kind(value : PreparedGraphRelation) -> GraphRelationKind {
  match value.params {
    EqualityGraphRelationParams => GraphsEqualRelation
    DiffGraphRelationParams(_, _) => GraphDiffRelation
    ApplyGraphParams(_, _) => ApplyGraphRelation
  }
}

///|
pub fn graph_relation_diff_contract(
  value : PreparedGraphRelation,
) -> @contract.Contract? {
  match value.params {
    DiffGraphRelationParams(contract, _) => Some(contract)
    _ => None
  }
}

///|
pub fn graph_relation_graph_contract_cid(
  value : PreparedGraphRelation,
) -> String? {
  match value.params {
    DiffGraphRelationParams(_, cid) => Some(cid)
    ApplyGraphParams(_, cid) => Some(cid)
    _ => None
  }
}

///|
pub fn graph_relation_apply_field(value : PreparedGraphRelation) -> String? {
  match value.params {
    ApplyGraphParams(field, _) => Some(field)
    _ => None
  }
}

///|
/// Resolve one ordered Graph operand to its exact producing step. Repeated
/// operands remain distinct input occurrences even when they share a producer.
pub fn graph_relation_input_step(
  value : PreparedGraphRelation,
  index : Int,
) -> Int? {
  match node_input_target(value.node, index) {
    Some(@pipeline.Step(step)) => Some(step)
    _ => None
  }
}

///|
pub fn graph_relation_output_schema(
  value : PreparedGraphRelation,
) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
priv enum PreparedGraphRelationParams {
  EqualityGraphRelationParams
  DiffGraphRelationParams(@contract.Contract, String)
  ApplyGraphParams(String, String)
}

///|
pub(all) enum GraphRelationIssue {
  InvalidGraphRelationLimits
  InvalidGraphRelationWiring
  GraphRelationPreparationLimit
} derive(Eq, Debug)

///|
fn prepare_graph_relation_node(
  node : PreparedNode,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphRelation, Int, Int, Int), GraphRelationIssue] {
  if max_entries < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidGraphRelationLimits)
  }
  let params = match node.payload {
    GraphEqualityRows(_) => EqualityGraphRelationParams
    GraphDiffRows(checked) =>
      DiffGraphRelationParams(
        @graph.diff_contract(checked),
        @graph_contract.cid(@graph.diff_graph_contract(checked)),
      )
    GraphApplyValue(checked) =>
      ApplyGraphParams(
        @graph.apply_field(checked),
        @graph_contract.cid(@graph.apply_graph_contract(checked)),
      )
    _ => return Err(InvalidGraphRelationWiring)
  }
  let (entries, name_bytes, work) = match params {
    EqualityGraphRelationParams | DiffGraphRelationParams(_, _) => (0, 0, 0)
    ApplyGraphParams(field, _) => (1, @utf8.encode(field).length(), 1)
  }
  if entries > max_entries || name_bytes > max_name_bytes || work > max_work {
    return Err(GraphRelationPreparationLimit)
  }
  Ok(({ node, params, }, entries, name_bytes, work))
}

///|
fn emit_graph_relation_node(
  prepared : PreparedGraphRelation,
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
  @encode.begin_object(out)
  match prepared.params {
    EqualityGraphRelationParams | DiffGraphRelationParams(_, _) => ()
    ApplyGraphParams(field, _) => {
      @encode.key(out, "field")
      @encode.string_value(out, field)
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
