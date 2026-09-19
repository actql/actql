///|
pub enum PathEndpoint {
  Single(@value.CheckedValue)
  Selected(CheckedSelector)
}

///|
pub(all) enum PathSelection {
  EachPair
  NearestPerSource
  NearestPair
} derive(Eq, Debug)

///|
pub(all) enum ShortestObligation {
  AdmitShortestGraph
  RequireEndpointMembership
  ValidateAllNonnegativeFiniteWeights
  FoldPathCostsWithOverrange
  RejectSelectedOverrangeAtomically
  SelectSimpleHopBoundedPaths
  ApplyCanonicalPathTieBreaks
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
  endpoints : Array[PathEndpoint]
  selection : PathSelection
  direction : Direction
  max_hops : Double
  types : Array[String]?
  weight : @row.FieldName?
  guard_rows : Count?
  output : @carrier.Carrier
  usage : PredicateUsage
}

///|
fn path_endpoint(
  b : Budget,
  source : @decode.Cursor,
  graph : @carrier.Carrier,
  relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  tokens : Int,
) -> (PathEndpoint, Int) raise {
  if @decode.view(source) is ObjectValue(_) {
    let s = match
      check_selector(source, graph, relation, parameters, {
        max_work: b.work,
        max_nodes: b.nodes,
        max_depth: b.limits.max_depth,
        max_text_bytes: b.text,
        max_tokens: tokens,
      }) {
      Ok(s) => s
      Err(e) => raise MatchStop(e)
    }
    b.work -= s.usage.work
    b.nodes -= s.usage.nodes
    b.text -= s.usage.text_bytes
    return (Selected(s), s.usage.tokens)
  }
  if relation is Some(_) {
    fail(source, InvalidBody)
  }
  guard graph is @carrier.GraphValue(g) else { fail(source, IncompleteGraph) }
  let before = b.nodes
  let before_text = b.text
  scan(b, source)
  match
    @value.admit(@carrier.graph_identity(g), source, {
      max_nodes: before - b.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: before_text - b.text,
    }) {
    Ok(v) => (Single(v), 0)
    Err(e) => raise MatchStop(MatchIdentity(e))
  }
}

///|
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
    guard input is @carrier.GraphValue(g) else {
      if @carrier.kind(input) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(input)))
      }
      fail(source, IncompleteGraph)
    }
    let root = decoded(
      @decode.closed_object(source, [
        "source", "target", "selection", "direction", "max_hops", "weight", "edge_types",
        "max_output_rows",
      ]),
    )
    let (start, start_tokens) = path_endpoint(
      b,
      decoded(@decode.required(root, "source")),
      input,
      source_relation,
      parameters,
      limits.max_tokens,
    )
    let (end, end_tokens) = path_endpoint(
      b,
      decoded(@decode.required(root, "target")),
      input,
      target_relation,
      parameters,
      limits.max_tokens - start_tokens,
    )
    let selection = if start is Single(_) && end is Single(_) {
      if @decode.lookup(root, "selection") is Some(at) {
        fail(at, InvalidBody)
      }
      EachPair
    } else {
      let at = decoded(@decode.required(root, "selection"))
      match decoded(@decode.text(at)) {
        "each_pair" => EachPair
        "nearest_per_source" => NearestPerSource
        "nearest_pair" => NearestPair
        _ => fail(at, InvalidBody)
      }
    }
    let direction = traversal_direction(
      decoded(@decode.required(root, "direction")),
    )
    let max_hops = traversal_bound(
      decoded(@decode.required(root, "max_hops")),
      1.0,
    )
    let types = traversal_types(b, @decode.lookup(root, "edge_types"), g)
    let weight = match @decode.lookup(root, "weight") {
      None => None
      Some(at) => {
        let name = decoded(@decode.text(at))
        let scope = match
          check_scope(Edges, at, input, {
            ..b.limits,
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
          }) {
          Ok(s) => s
          Err(e) => raise Stop(e)
        }
        b.work -= scope.usage.work
        b.text -= scope.usage.text_bytes
        spend(b, at, @carrier.field_count(scope.fields))
        let mut selected : @carrier.Field? = None
        for i in 0..<@carrier.field_count(scope.fields) {
          let f = @carrier.field_at(scope.fields, i).unwrap()
          if @row.reference_name(f.name) == name {
            selected = Some(f)
          }
        }
        let f = match selected {
          Some(f) => f
          None => fail(at, UnknownMatchField(name))
        }
        let c = match f.contract {
          Some(c) => c
          None => fail(at, UntypedMatchField(name))
        }
        if c.nullable || !(c.shape is @contract.Number) {
          fail(at, InvalidWeight)
        }
        Some(f.name)
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
      Ok(o) => o
      Err(e) => raise Stop(e)
    }
    b.work -= output.usage.work
    b.nodes -= output.usage.nodes
    b.text -= output.usage.text_bytes
    Ok({
      source,
      input,
      endpoints: [start, end],
      selection,
      direction,
      max_hops,
      types,
      weight,
      guard_rows,
      output: output.output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: start_tokens + end_tokens,
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected shortest-path checker exception")
  }
}

///|
pub fn shortest_source(c : CheckedShortest) -> @decode.Cursor {
  c.source
}

///|
pub fn shortest_endpoint(c : CheckedShortest, side : @row.Side) -> PathEndpoint {
  c.endpoints[if side == Left { 0 } else { 1 }]
}

///|
pub fn shortest_selection(c : CheckedShortest) -> PathSelection {
  c.selection
}

///|
pub fn shortest_direction(c : CheckedShortest) -> Direction {
  c.direction
}

///|
pub fn shortest_max_hops(c : CheckedShortest) -> Double {
  c.max_hops
}

///|
pub fn shortest_types(c : CheckedShortest) -> Array[String]? {
  c.types.map(xs => xs.copy())
}

///|
pub fn shortest_type_count(c : CheckedShortest) -> Int? {
  c.types.map(values => values.length())
}

///|
pub fn shortest_type_at(c : CheckedShortest, index : Int) -> String? {
  match c.types {
    Some(values) => values.get(index)
    None => None
  }
}

///|
pub fn shortest_weight(c : CheckedShortest) -> @row.FieldName? {
  c.weight
}

///|
pub fn shortest_output_guard(c : CheckedShortest) -> Count? {
  c.guard_rows
}

///|
pub fn shortest_output(c : CheckedShortest) -> @carrier.Carrier {
  c.output
}

///|
pub fn shortest_usage(c : CheckedShortest) -> PredicateUsage {
  c.usage
}

///|
pub fn shortest_pending(c : CheckedShortest) -> Array[ShortestObligation] {
  let out = []
  shortest_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn shortest_pending_each(
  c : CheckedShortest,
  emit : (ShortestObligation) -> Unit,
) -> Unit {
  emit(AdmitShortestGraph)
  emit(RequireEndpointMembership)
  emit(SelectSimpleHopBoundedPaths)
  emit(ApplyCanonicalPathTieBreaks)
  emit(CanonicalShortestOutputOrder)
  emit(ResolveShortestResources)
  emit(ResolveShortestProfile)
  if c.weight is Some(_) {
    emit(ValidateAllNonnegativeFiniteWeights)
    emit(FoldPathCostsWithOverrange)
    emit(RejectSelectedOverrangeAtomically)
  }
  if c.guard_rows is Some(bound) {
    emit(EnforceShortestOutputGuard)
    if bound is Parameter(name) {
      emit(BindShortestOutputGuard(name))
    }
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn shortest_pending_count(c : CheckedShortest) -> Int {
  let mut count = 0
  shortest_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn shortest_pending_at(
  c : CheckedShortest,
  index : Int,
) -> ShortestObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  shortest_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
pub fn shortest_input(c : CheckedShortest) -> @carrier.Carrier {
  c.input
}
