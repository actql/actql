///|
struct TraversalHop {
  direction : Direction
  types : Array[String]?
  edge_predicate : CheckedPredicate?
  node_predicate : CheckedPredicate?
}

///|
pub(all) enum TraverseObligation {
  AdmitTraversalGraph
  RespectTraversalHopBounds
  EvaluateTraversalHopPredicates
  EmitMinimumNodeDepth
  EnumerateSimplePaths
  DeduplicateExactPaths
  CanonicalTraversalOrder
  EnforceTraversalOutputGuard
  BindTraversalOutputGuard(String)
  ResolveTraversalResources
  ResolveTraversalProfile
} derive(Eq, Debug)

///|
struct CheckedTraverse {
  input : @carrier.Carrier
  source : @decode.Cursor
  start : CheckedSelector
  patterned : Bool
  minimum : Double
  maximum : Double
  hops : Array[TraversalHop]
  emit : PathOutput
  guard_rows : Count?
  output : @carrier.Carrier
  usage : PredicateUsage
}

///|
fn traversal_direction(c : @decode.Cursor) -> Direction raise Stop {
  match decoded(@decode.text(c)) {
    "in" => Incoming
    "out" => Outgoing
    "both" => Both
    _ => fail(c, InvalidBody)
  }
}

///|
fn traversal_types(
  b : Budget,
  at : @decode.Cursor?,
  g : @carrier.Graph,
) -> Array[String]? raise Stop {
  guard at is Some(at) else { return None }
  if @carrier.graph_label_contract(g) is None {
    fail(at, MissingEdgeLabel)
  }
  let xs = match @decode.view(at) {
    ArrayValue(xs) => xs
    _ => fail(at, InvalidBody)
  }
  spend(b, at, xs.length())
  let types = []
  for x in xs {
    let s = decoded(@decode.text(x))
    if s.is_empty() || @canonical.normalize_nfc_lf(s) != Ok(s) {
      fail(x, InvalidName(s))
    }
    types.push(s)
  }
  Some(types)
}

///|
fn traversal_bound(at : @decode.Cursor, minimum : Double) -> Double raise Stop {
  let n = decoded(@decode.finite_number(at))
  if n < minimum || @scalar.read_integer_number(n) is None {
    fail(at, InvalidCount)
  }
  n
}

///|
pub fn check_traverse(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  selector_relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedTraverse, MatchIssue] {
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
        "start", "hops", "direction", "edge_types", "min_hops", "max_hops", "emit",
        "max_output_rows",
      ]),
    )
    let at = decoded(@decode.required(root, "start"))
    let start = match
      check_selector(at, input, selector_relation, parameters, {
        ..limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(s) => s
      Err(e) => raise MatchStop(e)
    }
    b.work -= start.usage.work
    b.nodes -= start.usage.nodes
    b.text -= start.usage.text_bytes
    let mut tokens = start.usage.tokens
    let at = decoded(@decode.required(root, "emit"))
    let emit = match decoded(@decode.text(at)) {
      "nodes" => TraversedNodes
      "paths" => TraversedPaths
      _ => fail(at, InvalidBody)
    }
    let hops = []
    let patterned = @decode.lookup(root, "hops") is Some(_)
    let (minimum, maximum) = match @decode.lookup(root, "hops") {
      Some(at) => {
        for key in ["direction", "edge_types", "min_hops", "max_hops"] {
          if @decode.lookup(root, key) is Some(c) {
            fail(c, InvalidBody)
          }
        }
        let xs = match @decode.view(at) {
          ArrayValue(xs) => xs
          _ => fail(at, InvalidBody)
        }
        if xs.is_empty() {
          fail(at, InvalidBody)
        }
        spend(b, at, xs.length())
        for hop in xs {
          let o = decoded(
            @decode.closed_object(hop, [
              "direction", "edge_types", "edge_where", "node_where",
            ]),
          )
          let direction = traversal_direction(
            decoded(@decode.required(o, "direction")),
          )
          let types = traversal_types(b, @decode.lookup(o, "edge_types"), g)
          let predicates : Array[CheckedPredicate?] = []
          for (key, entity) in [("edge_where", Edges), ("node_where", Nodes)] {
            match @decode.lookup(o, key) {
              None => predicates.push(None)
              Some(c) => {
                let p = match
                  check_predicate(entity, c, input, parameters, {
                    ..limits,
                    max_work: b.work,
                    max_nodes: b.nodes,
                    max_text_bytes: b.text,
                    max_tokens: limits.max_tokens - tokens,
                  }) {
                  Ok(p) => p
                  Err(e) => raise MatchStop(MatchPredicate(e))
                }
                b.work -= p.usage.work
                b.nodes -= p.usage.nodes
                b.text -= p.usage.text_bytes
                tokens += p.usage.tokens
                predicates.push(Some(p))
              }
            }
          }
          hops.push({
            direction,
            types,
            edge_predicate: predicates[0],
            node_predicate: predicates[1],
          })
        }
        (xs.length().to_double(), xs.length().to_double())
      }
      None => {
        let direction = traversal_direction(
          decoded(@decode.required(root, "direction")),
        )
        let minimum = traversal_bound(
          decoded(@decode.required(root, "min_hops")),
          0.0,
        )
        let maximum = traversal_bound(
          decoded(@decode.required(root, "max_hops")),
          1.0,
        )
        if minimum > maximum {
          fail(source, InvalidCount)
        }
        let types = traversal_types(b, @decode.lookup(root, "edge_types"), g)
        spend(b, source, 1)
        hops.push({
          direction,
          types,
          edge_predicate: None,
          node_predicate: None,
        })
        (minimum, maximum)
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
      check_path_contract(emit, source, input, {
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
      start,
      patterned,
      minimum,
      maximum,
      hops,
      emit,
      guard_rows,
      output: output.output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens,
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected traversal checker exception")
  }
}

///|
pub fn traverse_source(c : CheckedTraverse) -> @decode.Cursor {
  c.source
}

///|
pub fn traverse_start(c : CheckedTraverse) -> CheckedSelector {
  c.start
}

///|
pub fn traverse_patterned(c : CheckedTraverse) -> Bool {
  c.patterned
}

///|
pub fn traverse_bounds(c : CheckedTraverse) -> (Double, Double) {
  (c.minimum, c.maximum)
}

///|
pub fn traverse_hop_count(c : CheckedTraverse) -> Int {
  c.hops.length()
}

///|
pub fn traverse_hop_at(c : CheckedTraverse, i : Int) -> TraversalHop? {
  c.hops.get(i)
}

///|
pub fn hop_direction(h : TraversalHop) -> Direction {
  h.direction
}

///|
pub fn hop_types(h : TraversalHop) -> Array[String]? {
  h.types.map(xs => xs.copy())
}

///|
pub fn hop_predicate(
  h : TraversalHop,
  entity : EntityKind,
) -> CheckedPredicate? {
  if entity == Nodes {
    h.node_predicate
  } else {
    h.edge_predicate
  }
}

///|
pub fn traverse_output(c : CheckedTraverse) -> @carrier.Carrier {
  c.output
}

///|
pub fn traverse_emission(c : CheckedTraverse) -> PathOutput {
  c.emit
}

///|
pub fn traverse_usage(c : CheckedTraverse) -> PredicateUsage {
  c.usage
}

///|
pub fn traverse_output_guard(c : CheckedTraverse) -> Count? {
  c.guard_rows
}

///|
pub fn traverse_pending(c : CheckedTraverse) -> Array[TraverseObligation] {
  let out = []
  traverse_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn traverse_pending_each(
  c : CheckedTraverse,
  emit : (TraverseObligation) -> Unit,
) -> Unit {
  emit(AdmitTraversalGraph)
  emit(RespectTraversalHopBounds)
  emit(EvaluateTraversalHopPredicates)
  emit(CanonicalTraversalOrder)
  emit(ResolveTraversalResources)
  emit(ResolveTraversalProfile)
  if c.emit == TraversedPaths {
    emit(EnumerateSimplePaths)
    emit(DeduplicateExactPaths)
  } else {
    emit(EmitMinimumNodeDepth)
  }
  if c.guard_rows is Some(bound) {
    emit(EnforceTraversalOutputGuard)
    if bound is Parameter(name) {
      emit(BindTraversalOutputGuard(name))
    }
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn traverse_pending_count(c : CheckedTraverse) -> Int {
  let mut count = 0
  traverse_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn traverse_pending_at(
  c : CheckedTraverse,
  index : Int,
) -> TraverseObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  traverse_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
pub fn traverse_input(c : CheckedTraverse) -> @carrier.Carrier {
  c.input
}
