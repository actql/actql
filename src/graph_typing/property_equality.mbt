///|
/// A current Property Graph comparison has two exact Graph ports. Compatible
/// definitions can have different producer provenance; the provenance remains
/// part of each runtime identity and therefore affects the Boolean result.
struct CheckedPropertyEquality {
  source : @decode.Cursor
  left : @carrier.Carrier
  right : @carrier.Carrier
  output : @carrier.Carrier
  usage : Usage
}

///|
pub(all) enum PropertyEqualityObligation {
  AdmitBothPropertyGraphs
  CompareCompleteGraphValues
  ResolvePropertyEqualityResources
} derive(Eq, Debug)

///|
pub fn property_equality_pending_count(_ : CheckedPropertyEquality) -> Int {
  3
}

///|
pub fn property_equality_pending_at(
  _ : CheckedPropertyEquality,
  index : Int,
) -> PropertyEqualityObligation? {
  match index {
    0 => Some(AdmitBothPropertyGraphs)
    1 => Some(CompareCompleteGraphValues)
    2 => Some(ResolvePropertyEqualityResources)
    _ => None
  }
}

///|
fn align_property_equality_definition(
  source : @decode.Cursor,
  left : @carrier.PropertyNodeDefinition,
  right : @carrier.PropertyNodeDefinition,
  b : Budget,
) -> Unit raise Stop {
  spend(b, source, 1)
  if @carrier.property_name_identity(@carrier.property_definition_name(left)) !=
    @carrier.property_name_identity(@carrier.property_definition_name(right)) {
    fail(source, IncompatibleGraphDomains)
  }
  let keys = @carrier.property_definition_key_count(left)
  if keys != @carrier.property_definition_key_count(right) {
    fail(source, IncompatibleGraphDomains)
  }
  for index in 0..<keys {
    spend(b, source, 1)
    let first = @carrier.property_definition_key_at(left, index).unwrap()
    let second = @carrier.property_definition_key_at(right, index).unwrap()
    let (joined, used) = @contract.join_nullability_usage(first, second, b.work) catch {
      _ => fail(source, BudgetExceeded)
    }
    spend(b, source, used)
    if joined is None {
      fail(source, IncompatibleGraphDomains)
    }
  }
  guard @carrier.complete_schema(@carrier.property_definition_properties(left))
    is Some(first_properties) &&
    @carrier.complete_schema(@carrier.property_definition_properties(right))
    is Some(second_properties) else {
    fail(source, IncompleteGraph)
  }
  ignore(align_domains(b, source, first_properties, second_properties))
  let labels = @carrier.property_definition_label_count(left)
  if labels != @carrier.property_definition_label_count(right) {
    fail(source, IncompatibleGraphDomains)
  }
  for index in 0..<labels {
    spend(b, source, 1)
    let (name, left_fields) = @carrier.property_definition_label_at(left, index).unwrap()
    let mut right_fields = None
    for other in 0..<labels {
      spend(b, source, 1)
      let (candidate, fields) = @carrier.property_definition_label_at(
        right, other,
      ).unwrap()
      if @carrier.property_name_identity(name) ==
        @carrier.property_name_identity(candidate) {
        right_fields = Some(fields)
        break
      }
    }
    guard right_fields is Some(right_fields) &&
      @carrier.complete_schema(left_fields) is Some(first) &&
      @carrier.complete_schema(right_fields) is Some(second) else {
      fail(source, IncompatibleGraphDomains)
    }
    ignore(align_domains(b, source, first, second))
  }
}

///|
fn align_property_equality_graphs(
  source : @decode.Cursor,
  left : @carrier.PropertyGraphDefinition,
  right : @carrier.PropertyGraphDefinition,
  b : Budget,
) -> Unit raise Stop {
  let nodes = @carrier.property_graph_node_count(left)
  let edges = @carrier.property_graph_edge_count(left)
  if nodes != @carrier.property_graph_node_count(right) ||
    edges != @carrier.property_graph_edge_count(right) {
    fail(source, IncompatibleGraphDomains)
  }
  for index in 0..<nodes {
    spend(b, source, 1)
    let first = @carrier.property_graph_node_at(left, index).unwrap()
    guard @carrier.property_graph_node_named(
        right,
        @carrier.property_definition_name(first),
      )
      is Some(second) else {
      fail(source, IncompatibleGraphDomains)
    }
    align_property_equality_definition(source, first, second, b)
  }
  for index in 0..<edges {
    spend(b, source, 1)
    let first = @carrier.property_graph_edge_at(left, index).unwrap()
    guard @carrier.property_graph_edge_named(
        right,
        @carrier.property_definition_name(@carrier.property_edge_element(first)),
      )
      is Some(second) else {
      fail(source, IncompatibleGraphDomains)
    }
    let (first_source, first_target) = @carrier.property_edge_endpoints(first)
    let (second_source, second_target) = @carrier.property_edge_endpoints(
      second,
    )
    if @carrier.property_name_identity(first_source) !=
      @carrier.property_name_identity(second_source) ||
      @carrier.property_name_identity(first_target) !=
      @carrier.property_name_identity(second_target) {
      fail(source, IncompatibleGraphDomains)
    }
    align_property_equality_definition(
      source,
      @carrier.property_edge_element(first),
      @carrier.property_edge_element(second),
      b,
    )
  }
}

///|
pub fn check_property_equality(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedPropertyEquality, Issue] {
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
    let body = decoded(@decode.closed_object(source, ["with"]))
    let other = decoded(@decode.required(body, "with"))
    let name = decoded(@decode.text(other))
    if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
      fail(other, InvalidName(name))
    }
    let first = match left {
      @carrier.GraphValue(graph) => graph
      @carrier.Opaque(GraphKind) => fail(source, IncompleteGraph)
      _ => fail(source, WrongCarrier(@carrier.kind(left)))
    }
    let second = match right {
      @carrier.GraphValue(graph) => graph
      @carrier.Opaque(GraphKind) => fail(other, IncompleteGraph)
      _ => fail(other, WrongCarrier(@carrier.kind(right)))
    }
    let first_definition = @carrier.graph_property_definition(first)
    let second_definition = @carrier.graph_property_definition(second)
    // A definition CID includes producer provenance. Compatible closed types
    // can therefore differ in CID while remaining valid equality operands.
    align_property_equality_graphs(
      other, first_definition, second_definition, b,
    )
    let output = diagnostic_rows(
      source,
      [
        (
          @row.Unqualified("equal"),
          Some(@contract.primitive(BooleanType, nullable=false)),
        ),
      ],
      b,
    )
    Ok({
      source,
      left,
      right,
      output,
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
pub fn property_equality_output(
  value : CheckedPropertyEquality,
) -> @carrier.Carrier {
  value.output
}

///|
pub fn property_equality_usage(value : CheckedPropertyEquality) -> Usage {
  value.usage
}

///|
pub fn property_equality_source(
  value : CheckedPropertyEquality,
) -> @decode.Cursor {
  value.source
}

///|
pub fn property_equality_input(
  value : CheckedPropertyEquality,
  right~ : Bool,
) -> @carrier.Carrier {
  if right {
    value.right
  } else {
    value.left
  }
}
