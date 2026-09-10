///|
pub(all) enum ReachObligation {
  AdmitReachGraph
  RequireReachStartMembership
  JournalReachExpansion
  BoundedMinimumDepthTraversal
  CanonicalReachOrder
  ResolveReachResources
  ResolveReachProfile
} derive(Eq, Debug)

///|
struct CheckedReach {
  source : @decode.Cursor
  start : @value.CheckedValue
  direction : Direction
  max_depth : Double
  output : @carrier.Carrier
  usage : Usage
}

///|
pub fn check_reach(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedReach, MatchIssue] {
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
    guard input is @carrier.GraphValue(g) else {
      if @carrier.kind(input) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(input)))
      }
      fail(source, IncompleteGraph)
    }
    let root = decoded(
      @decode.closed_object(source, ["start", "direction", "max_depth"]),
    )
    let at = decoded(@decode.required(root, "direction"))
    let direction = match decoded(@decode.text(at)) {
      "in" => Incoming
      "out" => Outgoing
      "both" => Both
      _ => fail(at, InvalidBody)
    }
    let at = decoded(@decode.required(root, "max_depth"))
    let maximum = decoded(@decode.finite_number(at))
    if @scalar.read_integer_number(maximum) is None || maximum <= 0.0 {
      fail(at, InvalidCount)
    }
    let at = decoded(@decode.required(root, "start"))
    let before = b.nodes
    let before_text = b.text
    scan(b, at)
    let id = @carrier.graph_identity(g)
    let start = match
      @value.admit(id, at, {
        max_nodes: before - b.nodes,
        max_depth: limits.max_depth,
        max_text_bytes: before_text - b.text,
      }) {
      Ok(v) => v
      Err(e) => raise MatchStop(MatchIdentity(e))
    }
    let fields : Array[(@row.FieldName, @contract.Contract?)] = [
      (Unqualified("start_id"), Some(id)),
      (Unqualified("node_id"), Some(id)),
      (
        Unqualified("depth"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
    ]
    if @carrier.graph_names(g) is Some(names) {
      let (name, _, _, _) = @carrier.graph_row_fields(names)
      if name != Unqualified("node_id") {
        fields.push((name, Some(id)))
      }
    }
    spend(b, source, fields.length())
    for (name, _) in fields {
      charge(b, source, @row.reference_name(name))
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(rows) => rows
      Err(@row.DuplicateField(name)) =>
        fail(source, ScopeCollision(@row.reference_name(name)))
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      source,
      start,
      direction,
      max_depth: maximum,
      output: @carrier.relation(rows),
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected reach checker exception")
  }
}

///|
pub fn reach_source(c : CheckedReach) -> @decode.Cursor {
  c.source
}

///|
pub fn reach_start(c : CheckedReach) -> @value.CheckedValue {
  c.start
}

///|
pub fn reach_direction(c : CheckedReach) -> Direction {
  c.direction
}

///|
pub fn reach_max_depth(c : CheckedReach) -> Double {
  c.max_depth
}

///|
pub fn reach_output(c : CheckedReach) -> @carrier.Carrier {
  c.output
}

///|
pub fn reach_usage(c : CheckedReach) -> Usage {
  c.usage
}

///|
pub fn reach_pending(_c : CheckedReach) -> Array[ReachObligation] {
  [
    AdmitReachGraph,
    RequireReachStartMembership,
    JournalReachExpansion,
    BoundedMinimumDepthTraversal,
    CanonicalReachOrder,
    ResolveReachResources,
    ResolveReachProfile,
  ]
}
