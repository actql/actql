///|
pub(all) enum UnionPropertyStrategy {
  UnionExactEqual
  UnionSetUnion
  UnionSetDifference
  UnionNumberSum
  UnionNumberMean
  UnionNumberMax
  UnionNumberMin
} derive(Eq, Debug)

///|
priv struct UnionField {
  left : Int
  right : Int
  strategy : UnionPropertyStrategy
}

///|
priv struct UnionDefinition {
  right : Int
  fields : Array[UnionField]
}

///|
priv struct UnionFold {
  output : @carrier.Carrier
  nodes : Array[UnionDefinition]
  edges : Array[UnionDefinition]
}

///|
/// One checked left fold. Every operand occurrence and positional alignment is
/// retained; neither repeated references nor equal values erase an application.
struct CheckedUnion {
  source : @decode.Cursor
  inputs : Array[@carrier.Carrier]
  folds : Array[UnionFold]
  node_strategies : Array[(String, UnionPropertyStrategy)]
  edge_strategies : Array[(String, UnionPropertyStrategy)]
  usage : Usage
}

///|
pub(all) enum UnionObligation {
  AdmitUnionInputs
  PreserveUnionIdentities
  CheckUnionEdgeEndpoints
  ApplyUnionPropertyStrategies
  CanonicalUnionOrder
  ResolveUnionResources
} derive(Eq, Debug)

///|
pub fn union_pending_count(_ : CheckedUnion) -> Int {
  6
}

///|
pub fn union_pending_at(_ : CheckedUnion, index : Int) -> UnionObligation? {
  match index {
    0 => Some(AdmitUnionInputs)
    1 => Some(PreserveUnionIdentities)
    2 => Some(CheckUnionEdgeEndpoints)
    3 => Some(ApplyUnionPropertyStrategies)
    4 => Some(CanonicalUnionOrder)
    5 => Some(ResolveUnionResources)
    _ => None
  }
}

///|
fn union_strategy_map(
  source : @decode.Cursor,
  b : Budget,
) -> Map[String, UnionPropertyStrategy] raise Stop {
  let object = decoded(@decode.open_object(source))
  let result : Map[String, UnionPropertyStrategy] = Map([])
  for name in decoded(@decode.object_field_names(source)) {
    spend(b, source, 1)
    let key = @carrier.graph_name_identity(name)
    if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
      fail(source, InvalidName(name))
    }
    if result.contains(key) {
      fail(source, DuplicateConstructionField(name))
    }
    let at = @decode.lookup(object, name).unwrap()
    let strategy = match decoded(@decode.text(at)) {
      "exact_equal" => UnionExactEqual
      "set_union" => UnionSetUnion
      "set_difference" => UnionSetDifference
      "number_sum" => UnionNumberSum
      "number_mean" => UnionNumberMean
      "number_max" => UnionNumberMax
      "number_min" => UnionNumberMin
      other => fail(at, InvalidPropertyStrategy(other))
    }
    result[key] = strategy
  }
  result
}

///|
fn union_join(
  source : @decode.Cursor,
  left : @contract.Contract,
  right : @contract.Contract,
  b : Budget,
) -> @contract.Contract raise Stop {
  let (value, used) = @contract.join_nullability_usage(left, right, b.work) catch {
    _ => fail(source, BudgetExceeded)
  }
  spend(b, source, used)
  match value {
    Some(value) => value
    None => fail(source, IncompatibleGraphDomains)
  }
}

///|
fn union_knowledge(
  source : @decode.Cursor,
  fields : Array[(@row.FieldName, @contract.Contract?)],
  b : Budget,
) -> @carrier.Knowledge raise Stop {
  spend(b, source, fields.length())
  let bytes = b.text
  for (name, _) in fields {
    charge(b, source, @row.reference_name(name))
  }
  match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=fields.length(),
      max_name_bytes=bytes,
    ) {
    Ok(value) => value
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn union_property_index(
  source : @decode.Cursor,
  properties : @carrier.Knowledge,
  name : String,
  b : Budget,
) -> Int raise Stop {
  let key = @carrier.graph_name_identity(name)
  for index in 0..<@carrier.field_count(properties) {
    spend(b, source, 1)
    let field = @carrier.field_at(properties, index).unwrap()
    if @carrier.graph_name_identity(@row.reference_name(field.name)) == key {
      return index
    }
  }
  fail(source, IncompatibleGraphDomains)
}

///|
fn union_definition(
  source : @decode.Cursor,
  left : @carrier.GraphNodeDefinition,
  right : @carrier.GraphNodeDefinition,
  strategies : Map[String, UnionPropertyStrategy],
  seen : Map[String, Bool],
  b : Budget,
) -> (@carrier.GraphNodeDefinition, Array[UnionField]) raise Stop {
  spend(b, source, 1)
  let name = @carrier.graph_element_definition_name(left)
  if name != @carrier.graph_element_definition_name(right) {
    fail(source, UnionDefinitionIdentityMismatch(name))
  }
  let keys = @carrier.graph_element_definition_key_count(left)
  if keys != @carrier.graph_element_definition_key_count(right) {
    fail(source, IncompatibleGraphDomains)
  }
  let key_contracts = []
  let key_columns = []
  for index in 0..<keys {
    spend(b, source, 1)
    let first = @carrier.graph_element_definition_key_column_at(left, index)
    let second = @carrier.graph_element_definition_key_column_at(right, index)
    if first.map(@carrier.graph_name_identity) !=
      second.map(@carrier.graph_name_identity) {
      fail(source, IncompatibleGraphDomains)
    }
    if first is Some(name) {
      key_columns.push(name)
    }
    let left_key = @carrier.graph_element_definition_key_at(left, index).unwrap()
    let right_key = @carrier.graph_element_definition_key_at(right, index).unwrap()
    let descriptor = @carrier.graph_key_descriptor(left_key)
    if descriptor is None ||
      descriptor != @carrier.graph_key_descriptor(right_key) {
      fail(source, UnionKeyIdentityMismatch(name, index))
    }
    let joined = union_join(source, left_key, right_key, b)
    if @carrier.graph_key_descriptor(joined) != descriptor {
      fail(source, UnionKeyIdentityMismatch(name, index))
    }
    key_contracts.push(joined)
  }
  let left_properties = @carrier.graph_element_definition_properties(left)
  let right_properties = @carrier.graph_element_definition_properties(right)
  let count = @carrier.field_count(left_properties)
  if count != @carrier.field_count(right_properties) {
    fail(source, IncompatibleGraphDomains)
  }
  let fields = []
  let alignment = []
  for index in 0..<count {
    spend(b, source, 1)
    let field = @carrier.field_at(left_properties, index).unwrap()
    let name = @row.reference_name(field.name)
    let key = @carrier.graph_name_identity(name)
    let other = union_property_index(source, right_properties, name, b)
    let right_field = @carrier.field_at(right_properties, other).unwrap()
    guard field.presence == @row.Required &&
      right_field.presence == @row.Required &&
      field.contract is Some(first) &&
      right_field.contract is Some(second) else {
      fail(source, IncompleteGraph)
    }
    let mut joined = union_join(source, first, second, b)
    let strategy = strategies.get(key).unwrap_or(UnionExactEqual)
    seen[key] = true
    match strategy {
      UnionExactEqual => ()
      UnionSetUnion | UnionSetDifference => {
        guard joined.shape is @contract.Array(items, max_items~) else {
          fail(source, IncompatiblePropertyStrategy(name))
        }
        // Union can retain all distinct items from both sides. An unbounded
        // contract is sound even across repeated authored fold occurrences;
        // execution must still bind finite storage and work ceilings.
        joined = @contract.array_contract(
          items,
          nullable=joined.nullable,
          max_items=if strategy == UnionSetUnion { None } else { max_items },
        ).unwrap()
      }
      _ =>
        if !(joined.shape is @contract.Number) {
          fail(source, IncompatiblePropertyStrategy(name))
        }
    }
    fields.push((field.name, Some(joined)))
    alignment.push({ left: index, right: other, strategy, })
  }
  let properties = union_knowledge(source, fields, b)
  let labels = @carrier.graph_element_definition_label_count(left)
  if labels != @carrier.graph_element_definition_label_count(right) {
    fail(source, IncompatibleGraphDomains)
  }
  let label_properties = []
  for index in 0..<labels {
    spend(b, source, 1)
    let (name, first) = @carrier.graph_element_definition_label_at(left, index).unwrap()
    let mut second = None
    for other in 0..<labels {
      spend(b, source, 1)
      let (candidate, fields) = @carrier.graph_element_definition_label_at(
        right, other,
      ).unwrap()
      if @carrier.graph_name_identity(name) ==
        @carrier.graph_name_identity(candidate) {
        second = Some(fields)
        break
      }
    }
    guard second is Some(second) else { fail(source, IncompatibleGraphDomains) }
    if @carrier.field_count(first) != @carrier.field_count(second) {
      fail(source, IncompatibleGraphDomains)
    }
    let exposed = []
    for field in @carrier.fields(first) {
      spend(b, source, 1)
      let field_name = @row.reference_name(field.name)
      ignore(union_property_index(source, second, field_name, b))
      let parent = union_property_index(source, properties, field_name, b)
      exposed.push(
        (field.name, @carrier.field_at(properties, parent).unwrap().contract),
      )
    }
    label_properties.push((name, union_knowledge(source, exposed, b)))
  }
  let name_bytes = b.text
  charge(b, source, @carrier.graph_element_definition_name(left))
  for name in key_columns {
    charge(b, source, name)
  }
  for name in @carrier.graph_element_definition_labels(left) {
    charge(b, source, name)
  }
  let (definition, used) = match
    @carrier.graph_node_definition_usage(
      @carrier.graph_element_definition_name(left),
      key_contracts,
      properties,
      @carrier.graph_element_definition_labels(left),
      max_fields=keys + count + labels,
      max_name_bytes=name_bytes,
      max_contract_work=b.work,
      key_columns~,
      label_properties~,
    ) {
    Ok(value) => value
    Err(@carrier.LimitExceeded) => fail(source, BudgetExceeded)
    Err(_) => fail(source, IncompatibleGraphDomains)
  }
  spend(b, source, used)
  (definition, alignment)
}

///|
fn union_graph_definition(
  source : @decode.Cursor,
  value : @carrier.Carrier,
) -> @carrier.GraphDefinition raise Stop {
  match value {
    @carrier.GraphValue(value) => @carrier.graph_definition(value)
    @carrier.Opaque(GraphKind) => fail(source, IncompleteGraph)
    _ => fail(source, WrongCarrier(@carrier.kind(value)))
  }
}

///|
fn union_fold(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  node_strategies : Map[String, UnionPropertyStrategy],
  edge_strategies : Map[String, UnionPropertyStrategy],
  b : Budget,
) -> UnionFold raise Stop {
  let first = union_graph_definition(source, left)
  let second = union_graph_definition(source, right)
  let nodes = @carrier.graph_node_count(first)
  let edges = @carrier.graph_edge_count(first)
  if @carrier.graph_domain(first) != @carrier.graph_domain(second) ||
    nodes != @carrier.graph_node_count(second) ||
    edges != @carrier.graph_edge_count(second) {
    fail(source, IncompatibleGraphDomains)
  }
  let node_definitions = []
  let edge_definitions = []
  let node_alignment = []
  let edge_alignment = []
  let seen_nodes : Map[String, Bool] = Map([])
  let seen_edges : Map[String, Bool] = Map([])
  for index in 0..<nodes {
    let definition = @carrier.graph_node_at(first, index).unwrap()
    let key = @carrier.graph_name_identity(
      @carrier.graph_element_definition_name(definition),
    )
    let mut matched = None
    for other in 0..<nodes {
      spend(b, source, 1)
      let candidate = @carrier.graph_node_at(second, other).unwrap()
      if @carrier.graph_name_identity(
          @carrier.graph_element_definition_name(candidate),
        ) ==
        key {
        matched = Some((other, candidate))
        break
      }
    }
    guard matched is Some((other, candidate)) else {
      fail(source, IncompatibleGraphDomains)
    }
    let (output, fields) = union_definition(
      source, definition, candidate, node_strategies, seen_nodes, b,
    )
    node_definitions.push(output)
    node_alignment.push({ right: other, fields, })
  }
  for index in 0..<edges {
    let definition = @carrier.graph_edge_at(first, index).unwrap()
    let element = @carrier.graph_edge_element(definition)
    let key = @carrier.graph_name_identity(
      @carrier.graph_element_definition_name(element),
    )
    let mut matched = None
    for other in 0..<edges {
      spend(b, source, 1)
      let candidate = @carrier.graph_edge_at(second, other).unwrap()
      if @carrier.graph_name_identity(
          @carrier.graph_element_definition_name(
            @carrier.graph_edge_element(candidate),
          ),
        ) ==
        key {
        matched = Some((other, candidate))
        break
      }
    }
    guard matched is Some((other, candidate)) else {
      fail(source, IncompatibleGraphDomains)
    }
    let (src, dst) = @carrier.graph_edge_endpoints(definition)
    let (other_src, other_dst) = @carrier.graph_edge_endpoints(candidate)
    if @carrier.graph_name_identity(src) !=
      @carrier.graph_name_identity(other_src) ||
      @carrier.graph_name_identity(dst) !=
      @carrier.graph_name_identity(other_dst) {
      fail(source, IncompatibleGraphDomains)
    }
    let (output, fields) = union_definition(
      source,
      element,
      @carrier.graph_edge_element(candidate),
      edge_strategies,
      seen_edges,
      b,
    )
    edge_definitions.push(
      @carrier.graph_edge_definition(output, src, dst).unwrap(),
    )
    edge_alignment.push({ right: other, fields, })
  }
  for (name, _) in node_strategies {
    spend(b, source, 1)
    if !seen_nodes.contains(name) {
      fail(source, UnknownMergeProperty(name))
    }
  }
  for (name, _) in edge_strategies {
    spend(b, source, 1)
    if !seen_edges.contains(name) {
      fail(source, UnknownMergeProperty(name))
    }
  }
  let (output, used) = match
    @carrier.graph_usage(
      @carrier.graph_domain(first),
      node_definitions,
      edge_definitions,
      max_definitions=nodes + edges,
      max_contract_work=b.work,
    ) {
    Ok(value) => value
    Err(@carrier.LimitExceeded) => fail(source, BudgetExceeded)
    Err(_) => fail(source, IncompatibleGraphDomains)
  }
  spend(b, source, used)
  { output, nodes: node_alignment, edges: edge_alignment, }
}

///|
/// Inputs are current Graph followed by each resolved authored peer occurrence.
/// Success is checked construction only, not an execution or capacity permit.
pub fn check_union(
  source : @decode.Cursor,
  inputs : Array[@carrier.Carrier],
  limits : Limits,
) -> Result[CheckedUnion, Issue] {
  check_structural_composition(source, inputs, limits, allow_list=true)
}

///|
/// Shared compatibility and field alignment construction. The operation's
/// closed operand form remains distinct; subtraction never admits a fold list.
fn check_structural_composition(
  source : @decode.Cursor,
  inputs : Array[@carrier.Carrier],
  limits : Limits,
  allow_list~ : Bool,
) -> Result[CheckedUnion, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let body = decoded(@decode.closed_object(source, ["with", "merge"]))
    let at = decoded(@decode.required(body, "with"))
    let peers = if @decode.array_length(at) is Some(count) {
      if !allow_list || count == 0 {
        fail(at, InvalidBody)
      }
      decoded(@decode.elements(at))
    } else {
      [at]
    }
    if inputs.length() != peers.length() + 1 {
      fail(at, InvalidBody)
    }
    for peer in peers {
      spend(b, peer, 1)
      let name = decoded(@decode.text(peer))
      if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
        fail(peer, InvalidName(name))
      }
    }
    let mut node_strategies : Map[String, UnionPropertyStrategy] = Map([])
    let mut edge_strategies : Map[String, UnionPropertyStrategy] = Map([])
    if @decode.lookup(body, "merge") is Some(at) {
      let merge = decoded(
        @decode.closed_object(at, ["node_properties", "edge_properties"]),
      )
      if @decode.lookup(merge, "node_properties") is Some(at) {
        node_strategies = union_strategy_map(at, b)
      }
      if @decode.lookup(merge, "edge_properties") is Some(at) {
        edge_strategies = union_strategy_map(at, b)
      }
    }
    let folds = []
    let mut output = inputs[0]
    for index in 1..<inputs.length() {
      spend(b, peers[index - 1], 1)
      let fold = union_fold(
        peers[index - 1],
        output,
        inputs[index],
        node_strategies,
        edge_strategies,
        b,
      )
      output = fold.output
      folds.push(fold)
    }
    let node_entries = []
    let edge_entries = []
    for (name, strategy) in node_strategies {
      spend(b, source, 1)
      node_entries.push((name, strategy))
    }
    for (name, strategy) in edge_strategies {
      spend(b, source, 1)
      edge_entries.push((name, strategy))
    }
    node_entries.sort_by((a, z) => @canonical.compare_utf16(a.0, z.0))
    edge_entries.sort_by((a, z) => @canonical.compare_utf16(a.0, z.0))
    Ok({
      source,
      inputs: inputs.copy(),
      folds,
      node_strategies: node_entries,
      edge_strategies: edge_entries,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn union_output(value : CheckedUnion) -> @carrier.Carrier {
  value.folds.last().unwrap().output
}

///|
pub fn union_source(value : CheckedUnion) -> @decode.Cursor {
  value.source
}

///|
pub fn union_usage(value : CheckedUnion) -> Usage {
  value.usage
}

///|
pub fn union_input_count(value : CheckedUnion) -> Int {
  value.inputs.length()
}

///|
pub fn union_input_at(value : CheckedUnion, index : Int) -> @carrier.Carrier? {
  value.inputs.get(index)
}

///|
pub fn union_fold_output(value : CheckedUnion, fold : Int) -> @carrier.Carrier? {
  value.folds.get(fold).map(fold => fold.output)
}

///|
pub fn union_right_definition(
  value : CheckedUnion,
  fold : Int,
  definition : Int,
  edge~ : Bool,
) -> Int? {
  value.folds
  .get(fold)
  .bind(fold => {
    (if edge { fold.edges } else { fold.nodes })
    .get(definition)
    .map(value => value.right)
  })
}

///|
pub fn union_field_at(
  value : CheckedUnion,
  fold : Int,
  definition : Int,
  property : Int,
  edge~ : Bool,
) -> (Int, Int, UnionPropertyStrategy)? {
  value.folds
  .get(fold)
  .bind(fold => {
    (if edge { fold.edges } else { fold.nodes })
    .get(definition)
    .bind(value => {
      value.fields
      .get(property)
      .map(value => (value.left, value.right, value.strategy))
    })
  })
}

///|
pub fn union_strategy_count(value : CheckedUnion, edge~ : Bool) -> Int {
  (if edge { value.edge_strategies } else { value.node_strategies }).length()
}

///|
pub fn union_strategy_at(
  value : CheckedUnion,
  index : Int,
  edge~ : Bool,
) -> (String, UnionPropertyStrategy)? {
  (if edge { value.edge_strategies } else { value.node_strategies }).get(index)
}

///|
pub fn union_strategy_name(value : UnionPropertyStrategy) -> String {
  match value {
    UnionExactEqual => "exact_equal"
    UnionSetUnion => "set_union"
    UnionSetDifference => "set_difference"
    UnionNumberSum => "number_sum"
    UnionNumberMean => "number_mean"
    UnionNumberMax => "number_max"
    UnionNumberMin => "number_min"
  }
}
