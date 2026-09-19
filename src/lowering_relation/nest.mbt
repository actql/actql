///|
/// One resolved correlation pair owned by the checked nest occurrence.
pub struct PreparedNestKey {
  left : @schema.FieldName
  right : @schema.FieldName
}

///|
/// One closed child-object field in authored projection order.
pub struct PreparedNestField {
  output : String
  input : @schema.FieldName
}

///|
/// One resolved child-order term. Stable input order completes equal terms.
pub struct PreparedNestOrder {
  field : @schema.FieldName
  descending : Bool
  nulls_first : Bool
  authored : Bool
}

///|
/// Canonical identity projection for one opaque reference field.
priv struct PreparedNestReference {
  field : @schema.FieldName
  projected_name : String
  identity_field : String
}

///|
/// One node in the registered finite expansion of a nest occurrence.
priv struct PreparedNestExpansionNode {
  role : String
  operation : String
  inputs : Int
  source_node : Bool
} derive(Eq)

///|
fn nest_generated_role_id(step : Int, role : String) -> String {
  "nest_" + role + "_" + step.to_string()
}

///|
fn prepare_source_nest_expansion(
  owner : @pipeline.CheckedPipeline,
  step : Int,
  checked : @nest.CheckedNest,
) -> Array[PreparedNestExpansionNode] {
  let ordered = match
    @pipeline.resolve_nest_order(
      owner,
      step,
      max_work=2147483647,
      max_text_bytes=2147483647,
    ) {
    Ok(resolved) =>
      @pipeline.nest_order_strategy(resolved) != @pipeline.Inherited &&
      @pipeline.nest_order_term_count(resolved) > 0
    Err(_) => @nest.order_count(checked) is Some(_)
  }
  prepare_nest_expansion(
    nest_schema_has_references(@nest.input_schema(checked, @schema.Left)),
    nest_schema_has_references(@nest.input_schema(checked, @schema.Right)),
    ordered,
  )
}

///|
fn prepare_nest_expansion(
  parent_references : Bool,
  child_references : Bool,
  ordered : Bool,
) -> Array[PreparedNestExpansionNode] {
  let nodes : Array[PreparedNestExpansionNode] = []
  if parent_references {
    nodes.push({
      role: "parent_refs",
      operation: "REL.derive",
      inputs: 1,
      source_node: false,
    })
  }
  if child_references {
    nodes.push({
      role: "child_refs",
      operation: "REL.derive",
      inputs: 1,
      source_node: false,
    })
  }
  nodes.push({
    role: "matched",
    operation: "REL.join",
    inputs: 2,
    source_node: false,
  })
  nodes.push({
    role: "children",
    operation: "REL.select",
    inputs: 1,
    source_node: false,
  })
  if ordered {
    nodes.push({
      role: "ordered",
      operation: "REL.orderByStable",
      inputs: 1,
      source_node: false,
    })
  }
  nodes.push({
    role: "grouped",
    operation: "REL.groupBy",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "none",
    operation: "REL.where",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "empty",
    operation: "REL.groupBy",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "attached",
    operation: "REL.join",
    inputs: 2,
    source_node: false,
  })
  nodes.push({
    role: "parents",
    operation: "REL.select",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "empty_attached",
    operation: "REL.join",
    inputs: 2,
    source_node: false,
  })
  nodes.push({
    role: "flat",
    operation: "REL.select",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "filled",
    operation: "REL.derive",
    inputs: 1,
    source_node: false,
  })
  nodes.push({
    role: "",
    operation: "REL.select",
    inputs: 1,
    source_node: true,
  })
  nodes
}

///|
fn nest_expansion_reference_count(
  expansion : Array[PreparedNestExpansionNode],
) -> Int {
  let mut count = 0
  for node in expansion {
    count += node.inputs
  }
  count
}

///|
fn nest_expansion_has_role(
  expansion : Array[PreparedNestExpansionNode],
  role : String,
) -> Bool {
  expansion.any(node => node.role == role)
}

///|
fn nest_schema_has_references(schema : @schema.Schema) -> Bool {
  for index in 0..<@schema.field_count(schema) {
    match @schema.field_at(schema, index).unwrap().contract.shape {
      @contract.ResourceRef(..) | @contract.ArtifactRef(..) => return true
      _ => ()
    }
  }
  false
}

///|
/// Complete owner-bound nest input. This view resolves the checked order and
/// authored guard once; execution never reopens author source.
struct PreparedNestKernel {
  owner : BoundPrepared
  step : Int
  checked : @nest.CheckedNest
  keys : Array[PreparedNestKey]
  fields : Array[PreparedNestField]
  order : Array[PreparedNestOrder]
  parent_references : Array[PreparedNestReference]
  child_references : Array[PreparedNestReference]
  inherited_order : Bool
  expansion : Array[PreparedNestExpansionNode]
  item_limit : Int64?
}

///|
pub(all) enum NestIssue {
  InvalidNestLimits
  MissingNestNode
  InvalidNestWiring
  NestPreparationLimit
  NestOrderFailure(@pipeline.IssueKind)
  MissingNestParameter(String)
  InvalidNestParameter(String)
} derive(Eq, Debug)

///|
pub fn prepare_nest_kernel(
  owner : BoundPrepared,
  step : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedNestKernel, Int, Int, Int), NestIssue] {
  if max_entries < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidNestLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is NestRows(checked) else {
    return Err(MissingNestNode)
  }
  guard node.inputs.length() == 2 && node.input_targets.length() == 2 else {
    return Err(InvalidNestWiring)
  }
  let key_count = @nest.key_count(checked)
  let field_count = @nest.projection_count(checked)
  if key_count > max_entries || field_count > max_entries - key_count {
    return Err(NestPreparationLimit)
  }
  let keys : Array[PreparedNestKey] = []
  let fields : Array[PreparedNestField] = []
  let mut names = 0
  let mut work = key_count + field_count
  let spend_name = fn(name : String) -> Bool {
    if name.length() > max_name_bytes - names {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - names {
      return false
    }
    names += bytes
    true
  }
  for index in 0..<key_count {
    let pair = @nest.key_at(checked, index).unwrap()
    if !spend_name(@schema.reference_name(pair.left)) ||
      !spend_name(@schema.reference_name(pair.right)) {
      return Err(NestPreparationLimit)
    }
    keys.push({ left: pair.left, right: pair.right, })
  }
  for index in 0..<field_count {
    let field = @nest.projection_at(checked, index).unwrap()
    if !spend_name(field.output) ||
      !spend_name(@schema.reference_name(field.input)) {
      return Err(NestPreparationLimit)
    }
    fields.push({ output: field.output, input: field.input, })
  }
  let prepare_references = fn(
    schema : @schema.Schema,
  ) -> Array[PreparedNestReference]? {
    let references : Array[PreparedNestReference] = []
    for index in 0..<@schema.field_count(schema) {
      if work >= max_work {
        return None
      }
      work += 1
      let field = @schema.field_at(schema, index).unwrap()
      let identity_field = match field.contract.shape {
        @contract.ResourceRef(..) => "identity_cid"
        @contract.ArtifactRef(..) => "artifact_ref_cid"
        _ => continue
      }
      let projected_name = "__actql_nest_ref_" + index.to_string()
      if references.length() >= max_entries - key_count - field_count ||
        !spend_name(@schema.reference_name(field.name)) ||
        !spend_name(projected_name) {
        return None
      }
      references.push({ field: field.name, projected_name, identity_field, })
    }
    Some(references)
  }
  guard prepare_references(@nest.input_schema(checked, @schema.Left))
    is Some(parent_references) &&
    prepare_references(@nest.input_schema(checked, @schema.Right))
    is Some(child_references) else {
    return Err(NestPreparationLimit)
  }
  if parent_references.length() + child_references.length() >
    max_entries - key_count - field_count {
    return Err(NestPreparationLimit)
  }
  if work > max_work {
    return Err(NestPreparationLimit)
  }
  let resolved = match
    @pipeline.resolve_nest_order(
      owner.prepared.owner,
      step,
      max_work=max_work - work,
      max_text_bytes=max_name_bytes - names,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NestOrderFailure(issue.kind))
  }
  let order_count = @pipeline.nest_order_term_count(resolved)
  if order_count >
    max_entries -
    key_count -
    field_count -
    parent_references.length() -
    child_references.length() {
    return Err(NestPreparationLimit)
  }
  let order : Array[PreparedNestOrder] = []
  for index in 0..<order_count {
    let term = @pipeline.nest_order_term_at(resolved, index).unwrap()
    order.push({
      field: term.field,
      descending: term.direction == @order.Desc,
      nulls_first: term.nulls == @order.First,
      authored: term.authored,
    })
  }
  let (order_work, order_text) = @pipeline.nest_order_usage(resolved)
  work += order_work
  names += order_text
  let item_limit = match @nest.item_guard(checked) {
    None => None
    Some(@nest.Literal(value)) => Some(value)
    Some(@nest.Parameter(name)) => {
      if !spend_name(name) {
        return Err(NestPreparationLimit)
      }
      work += 1
      guard parameter_value(owner, name) is Some(value) else {
        return Err(MissingNestParameter(name))
      }
      guard value.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(value) &&
        value > 0L else {
        return Err(InvalidNestParameter(name))
      }
      Some(value)
    }
  }
  if work > max_work || names > max_name_bytes {
    return Err(NestPreparationLimit)
  }
  let entries = key_count +
    field_count +
    order_count +
    parent_references.length() +
    child_references.length()
  let order_strategy = @pipeline.nest_order_strategy(resolved)
  let expansion = prepare_nest_expansion(
    !parent_references.is_empty(),
    !child_references.is_empty(),
    order_strategy != @pipeline.Inherited && !order.is_empty(),
  )
  guard node.nest_expansion is Some(prepared_expansion) &&
    prepared_expansion == expansion else {
    return Err(InvalidNestWiring)
  }
  Ok(
    (
      {
        owner,
        step,
        checked,
        keys,
        fields,
        order,
        parent_references,
        child_references,
        inherited_order: @pipeline.nest_order_inherited(resolved) is Some(_),
        expansion,
        item_limit,
      },
      entries,
      names,
      work,
    ),
  )
}

///|
pub fn nest_kernel_owner(value : PreparedNestKernel) -> BoundPrepared {
  value.owner
}

///|
pub fn nest_kernel_step(value : PreparedNestKernel) -> Int {
  value.step
}

///|
pub fn nest_kernel_input(value : PreparedNestKernel, parent : Bool) -> String {
  value.owner.prepared.nodes[value.step].inputs[if parent { 0 } else { 1 }]
}

///|
pub fn nest_kernel_checked(value : PreparedNestKernel) -> @nest.CheckedNest {
  value.checked
}

///|
pub fn nest_kernel_key_count(value : PreparedNestKernel) -> Int {
  value.keys.length()
}

///|
pub fn nest_kernel_key_at(
  value : PreparedNestKernel,
  index : Int,
) -> PreparedNestKey? {
  value.keys.get(index)
}

///|
pub fn nest_kernel_field_count(value : PreparedNestKernel) -> Int {
  value.fields.length()
}

///|
pub fn nest_kernel_field_at(
  value : PreparedNestKernel,
  index : Int,
) -> PreparedNestField? {
  value.fields.get(index)
}

///|
pub fn nest_kernel_order_count(value : PreparedNestKernel) -> Int {
  value.order.length()
}

///|
pub fn nest_kernel_order_at(
  value : PreparedNestKernel,
  index : Int,
) -> PreparedNestOrder? {
  value.order.get(index)
}

///|
pub fn nest_kernel_inherits_order(value : PreparedNestKernel) -> Bool {
  value.inherited_order
}

///|
pub fn nest_kernel_item_limit(value : PreparedNestKernel) -> Int64? {
  value.item_limit
}

///|
pub fn nest_kernel_into(value : PreparedNestKernel) -> String {
  @nest.into(value.checked)
}

///|
pub fn nest_kernel_output_schema(value : PreparedNestKernel) -> @schema.Schema {
  @nest.output_schema(value.checked)
}

///|
pub fn nest_kernel_input_schema(
  value : PreparedNestKernel,
  parent : Bool,
) -> @schema.Schema {
  @nest.input_schema(
    value.checked,
    if parent {
      @schema.Left
    } else {
      @schema.Right
    },
  )
}
