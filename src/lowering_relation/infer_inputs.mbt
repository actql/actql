///|
pub(all) enum InferInputIssueKind {
  InvalidLimits
  BudgetExceeded
  Binding(BindingIssueKind)
  MissingCheckedInput
  MissingResolvedField(String)
  MissingItemGuard(String)
  InvalidItemGuard(String)
  Expression(ExpressionIssueKind)
}

///|
pub struct InferInputIssue {
  kind : InferInputIssueKind
  source : @decode.Cursor
}

///|
struct PreparedInferInputs {
  owner : @infer.CheckedInfer
  parameters : @parameter.BoundValues?
  inputs : Array[Expression]
  item_guard : Int64?
  usage : (Int, Int, Int, Int)
}

///|
/// Prepares only the checked mapped expressions. This does not preflight call
/// slots, adapter transport, classification, media or execution authority.
pub fn prepare_infer_inputs(
  owner : @infer.CheckedInfer,
  parameters : @parameter.BoundValues?,
  limits : ExpressionLimits,
  expression_profiles? : ExpressionProfileAdmission = {
    text_time: false,
    veca: false,
  },
) -> Result[PreparedInferInputs, InferInputIssue] {
  let source = @infer.source(owner)
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_literal_nodes < 0 ||
    limits.max_literal_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  let (by_name, parameter_count, parameter_bytes) = match
    resolve_expression_bindings(
      source,
      @infer.parameters(owner),
      parameters,
      limits.max_work,
      limits.max_literal_text_bytes,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err({ kind: Binding(issue.kind), source: issue.source, })
  }
  let count = @infer.input_binding_count(owner)
  let mut work = limits.max_work - parameter_count
  if count > work || count > limits.max_nodes {
    return Err({ kind: BudgetExceeded, source, })
  }
  work -= count
  let mut nodes = limits.max_nodes
  let mut literal_nodes = limits.max_literal_nodes
  let mut text_bytes = limits.max_literal_text_bytes - parameter_bytes
  let item_guard = match @infer.max_items_guard(owner) {
    None => None
    Some(authored) => {
      let guard_source = @relation.count_value_source(authored)
      if work == 0 {
        return Err({ kind: BudgetExceeded, source, })
      }
      work -= 1
      match @relation.count_value(authored) {
        Literal(value) => Some(value)
        Parameter(name) => {
          if name.length() > text_bytes {
            return Err({ kind: BudgetExceeded, source, })
          }
          let bytes = @utf8.encode(name).length()
          if bytes > text_bytes {
            return Err({ kind: BudgetExceeded, source, })
          }
          text_bytes -= bytes
          guard by_name.get(name) is Some(value) else {
            return Err({ kind: MissingItemGuard(name), source: guard_source, })
          }
          guard value.value is @value.Number(number) &&
            @scalar.read_safe_integer(number) is Some(value) &&
            value > 0L else {
            return Err({ kind: InvalidItemGuard(name), source: guard_source, })
          }
          Some(value)
        }
      }
    }
  }
  let inputs = []
  for index in 0..<count {
    guard @infer.input_binding_at(owner, index) is Some(binding) else {
      return Err({ kind: MissingCheckedInput, source, })
    }
    let syntax = @typing.expression(binding.expression)
    let size = @syntax.relation_reference_count(syntax)
    if size > work || size > nodes {
      return Err({ kind: BudgetExceeded, source: binding.source, })
    }
    work -= size
    let references = []
    for i in 0..<size {
      let reference = @syntax.relation_reference_at(syntax, i).unwrap()
      guard @schema.lookup_reference(@infer.input_schema(owner), reference.name)
        is Some(field) else {
        return Err({
          kind: MissingResolvedField(reference.name),
          source: reference.location.source,
        })
      }
      references.push((reference.name, @relation.InputField(field.name)))
    }
    let (expression, used) = match
      lower_typed_expression_measured(
        binding.expression,
        references,
        by_name,
        profile => {
          selected_expression_profile_admitted(expression_profiles, profile)
        },
        {
          max_work: work,
          max_nodes: nodes,
          max_depth: limits.max_depth,
          max_literal_nodes: literal_nodes,
          max_literal_text_bytes: text_bytes,
        },
      ) {
      Ok(value) => value
      Err(issue) =>
        return Err({ kind: Expression(issue.kind), source: issue.source, })
    }
    work -= used.work
    nodes -= used.nodes
    literal_nodes -= used.literal_nodes
    text_bytes -= used.literal_bytes
    inputs.push(expression)
  }
  Ok({
    owner,
    parameters,
    inputs,
    item_guard,
    usage: (
      limits.max_work - work,
      limits.max_nodes - nodes,
      limits.max_literal_nodes - literal_nodes,
      limits.max_literal_text_bytes - text_bytes,
    ),
  })
}

///|
pub fn infer_inputs_owner(value : PreparedInferInputs) -> @infer.CheckedInfer {
  value.owner
}

///|
pub fn infer_inputs_parameters(
  value : PreparedInferInputs,
) -> @parameter.BoundValues? {
  value.parameters
}

///|
/// The author's bound item guard under the exact parameter declaration owner.
/// It is not a resolved limit or model-egress authority.
pub fn infer_input_item_guard(value : PreparedInferInputs) -> Int64? {
  value.item_guard
}

///|
pub fn infer_input_count(value : PreparedInferInputs) -> Int {
  value.inputs.length()
}

///|
pub fn infer_input_expression_at(
  value : PreparedInferInputs,
  index : Int,
) -> Expression? {
  value.inputs.get(index)
}

///|
pub fn infer_inputs_usage(value : PreparedInferInputs) -> (Int, Int, Int, Int) {
  value.usage
}

///|
/// Check the acquisition's exact output binding without exposing a generic
/// frontend payload to the execution engine. This does not execute Infer or
/// authorize a model call.
pub fn infer_output_binding(
  owner : BoundPrepared,
  step : Int,
  infer : @infer.CheckedInfer,
  input : @pipeline.Target,
) -> String? {
  guard node_at(bound_preparation(owner), step) is Some(node) &&
    node.payload is Infer(checked) &&
    physical_equal(checked, infer) &&
    node_input_count(node) == 1 &&
    node_input_target(node, 0) == Some(input) else {
    return None
  }
  Some(node.id)
}
