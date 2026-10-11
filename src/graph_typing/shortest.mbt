///|
pub(all) enum ShortestSelection {
  EachPair
  NearestPerSource
  NearestPair
} derive(Eq, Debug)

///|
pub(all) enum ShortestObligation {
  AdmitShortestGraph
  AdmitShortestSelectors
  DeduplicateShortestSelectors
  RequireShortestMembership
  ValidateEveryShortestWeight
  RespectShortestHopBound
  EnumerateSimpleShortestPaths
  SelectCanonicalShortestPaths
  RejectSelectedOverrange
  CanonicalShortestOutputOrder
  EnforceShortestOutputGuard
  BindShortestOutputGuard(String)
  ResolveShortestResources
  ResolveShortestProfile
} derive(Eq, Debug)

///|
struct CheckedShortest {
  input : @carrier.Carrier
  source : @decode.Cursor
  starts : CheckedSelector
  targets : CheckedSelector
  selection : ShortestSelection
  direction : Direction
  maximum_hops : Double
  edge_types : Array[String]?
  weight : String?
  weight_positions : Array[Int]
  guard_rows : Count?
  output : @carrier.Carrier
  usage : PredicateUsage
}

///|
fn shortest_set_selector(source : @decode.Cursor) -> Bool {
  match @decode.open_object(source) {
    Ok(root) =>
      ["ids", "from", "where"].any(key => @decode.lookup(root, key) is Some(_))
    Err(_) => false
  }
}

///|
// Weight admission applies to every declared edge definition, not merely the
// definitions reached by this search or retained by its edge label filter.
fn shortest_weight_positions(
  graph : @carrier.Graph,
  source : @decode.Cursor,
  name : String,
  budget : Budget,
) -> Array[Int] raise Stop {
  let profile = @carrier.graph_definition(graph)
  let positions = []
  if @carrier.graph_edge_count(profile) == 0 {
    fail(source, InvalidWeight)
  }
  for index in 0..<@carrier.graph_edge_count(profile) {
    spend(budget, source, 1)
    let properties = @carrier.graph_element_definition_properties(
      @carrier.graph_edge_element(
        @carrier.graph_edge_at(profile, index).unwrap(),
      ),
    )
    let mut found = None
    for field_index in 0..<@carrier.field_count(properties) {
      spend(budget, source, 1)
      let field = @carrier.field_at(properties, field_index).unwrap()
      if @row.reference_name(field.name).to_lower() == name.to_lower() {
        guard field.contract is Some(contract) &&
          contract.shape is @contract.Number &&
          !contract.nullable &&
          field.presence == @row.Required else {
          fail(source, InvalidWeight)
        }
        found = Some(field_index)
      }
    }
    guard found is Some(position) else { fail(source, InvalidWeight) }
    positions.push(position)
  }
  positions
}

///|
/// Check the current typed path profile. Runtime membership and observed edge
/// costs remain obligations of the bounded owner; this does not admit dispatch.
pub fn check_shortest(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  source_relation : @carrier.Carrier?,
  target_relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedShortest, MatchIssue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidLimits)
    }
    guard input is @carrier.GraphValue(graph) else {
      if @carrier.kind(input) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(input)))
      }
      fail(source, IncompleteGraph)
    }
    let b : Budget = {
      limits: {
        max_work: limits.max_work,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_text_bytes,
      },
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let root = decoded(
      @decode.closed_object(source, [
        "source", "target", "selection", "direction", "max_hops", "weight", "edge_types",
        "max_output_rows",
      ]),
    )
    let source_at = decoded(@decode.required(root, "source"))
    let target_at = decoded(@decode.required(root, "target"))
    let starts = match
      check_reach_selector(source_at, input, source_relation, parameters, {
        ..limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(value) => value
      Err(issue) => raise MatchStop(issue)
    }
    b.work -= starts.usage.work
    b.nodes -= starts.usage.nodes
    b.text -= starts.usage.text_bytes
    let targets = match
      check_reach_selector(target_at, input, target_relation, parameters, {
        ..limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
        max_tokens: limits.max_tokens - starts.usage.tokens,
      }) {
      Ok(value) => value
      Err(issue) => raise MatchStop(issue)
    }
    b.work -= targets.usage.work
    b.nodes -= targets.usage.nodes
    b.text -= targets.usage.text_bytes
    let selection = match @decode.lookup(root, "selection") {
      None => {
        if shortest_set_selector(source_at) || shortest_set_selector(target_at) {
          fail(source, InvalidBody)
        }
        EachPair
      }
      Some(at) => {
        if !shortest_set_selector(source_at) &&
          !shortest_set_selector(target_at) {
          fail(at, InvalidBody)
        }
        match decoded(@decode.text(at)) {
          "each_pair" => EachPair
          "nearest_per_source" => NearestPerSource
          "nearest_pair" => NearestPair
          _ => fail(at, InvalidBody)
        }
      }
    }
    let direction = traversal_direction(
      decoded(@decode.required(root, "direction")),
    )
    let maximum_hops = traversal_bound(
      decoded(@decode.required(root, "max_hops")),
      1.0,
    )
    let edge_types = traversal_types(b, @decode.lookup(root, "edge_types"))
    let (weight, weight_positions) = match @decode.lookup(root, "weight") {
      None => (None, [])
      Some(at) => {
        let name = decoded(@decode.text(at))
        if name.is_empty() {
          fail(at, InvalidWeight)
        }
        let positions = shortest_weight_positions(graph, at, name, b)
        (Some(name), positions)
      }
    }
    let guard_rows = match @decode.lookup(root, "max_output_rows") {
      None => None
      Some(at) => {
        let params : Map[String, @contract.Contract] = Map([])
        if parameters is Some(ds) {
          spend(b, at, @parameter.declaration_count(ds))
          for i in 0..<@parameter.declaration_count(ds) {
            let d = @parameter.declaration_at(ds, i).unwrap()
            charge(b, at, d.name)
            params[d.name] = d.parameter_type.contract
          }
        }
        Some(count(at, params))
      }
    }
    let output = match
      check_path_contract(ShortestPaths, source, input, {
        ..b.limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(value) => value
      Err(issue) => raise Stop(issue)
    }
    b.work -= output.usage.work
    b.nodes -= output.usage.nodes
    b.text -= output.usage.text_bytes
    Ok({
      input,
      source,
      starts,
      targets,
      selection,
      direction,
      maximum_hops,
      edge_types,
      weight,
      weight_positions,
      guard_rows,
      output: output.output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: starts.usage.tokens + targets.usage.tokens,
      },
    })
  } catch {
    Stop(issue) => Err(MatchStructure(issue))
    MatchStop(issue) => Err(issue)
    _ => abort("unexpected shortest path checker exception")
  }
}

///|
pub fn shortest_input(value : CheckedShortest) -> @carrier.Carrier {
  value.input
}

///|
pub fn shortest_source(value : CheckedShortest) -> @decode.Cursor {
  value.source
}

///|
pub fn shortest_starts(value : CheckedShortest) -> CheckedSelector {
  value.starts
}

///|
pub fn shortest_targets(value : CheckedShortest) -> CheckedSelector {
  value.targets
}

///|
pub fn shortest_selection(value : CheckedShortest) -> ShortestSelection {
  value.selection
}

///|
pub fn shortest_direction(value : CheckedShortest) -> Direction {
  value.direction
}

///|
pub fn shortest_maximum_hops(value : CheckedShortest) -> Double {
  value.maximum_hops
}

///|
pub fn shortest_edge_type_count(value : CheckedShortest) -> Int? {
  value.edge_types.map(xs => xs.length())
}

///|
pub fn shortest_edge_type_at(value : CheckedShortest, index : Int) -> String? {
  value.edge_types.bind(xs => xs.get(index))
}

///|
pub fn shortest_weight(value : CheckedShortest) -> String? {
  value.weight
}

///|
pub fn shortest_weight_position(
  value : CheckedShortest,
  definition : Int,
) -> Int? {
  value.weight_positions.get(definition)
}

///|
pub fn shortest_output_guard(value : CheckedShortest) -> Count? {
  value.guard_rows
}

///|
pub fn shortest_output(value : CheckedShortest) -> @carrier.Carrier {
  value.output
}

///|
pub fn shortest_usage(value : CheckedShortest) -> PredicateUsage {
  value.usage
}

///|
pub fn shortest_pending(value : CheckedShortest) -> Array[ShortestObligation] {
  let pending = []
  shortest_pending_each(value, item => pending.push(item))
  pending
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn shortest_pending_count(value : CheckedShortest) -> Int {
  let mut count = 0
  shortest_pending_each(value, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn shortest_pending_at(
  value : CheckedShortest,
  index : Int,
) -> ShortestObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  shortest_pending_each(value, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
fn shortest_pending_each(
  value : CheckedShortest,
  emit : (ShortestObligation) -> Unit,
) -> Unit {
  emit(AdmitShortestGraph)
  emit(AdmitShortestSelectors)
  emit(DeduplicateShortestSelectors)
  emit(RequireShortestMembership)
  emit(ValidateEveryShortestWeight)
  emit(RespectShortestHopBound)
  emit(EnumerateSimpleShortestPaths)
  emit(SelectCanonicalShortestPaths)
  emit(RejectSelectedOverrange)
  emit(CanonicalShortestOutputOrder)
  emit(ResolveShortestResources)
  emit(ResolveShortestProfile)
  match value.guard_rows {
    Some(Parameter(name)) => emit(BindShortestOutputGuard(name))
    Some(Literal(_)) => emit(EnforceShortestOutputGuard)
    None => ()
  }
}
