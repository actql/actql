///|
/// Checked diagnostic thresholds retain their authored occurrence and typed
/// parameter references. They are not observed Graph sizes or capacity limits.
struct CheckedGraphBounds {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  max_nodes : Count?
  max_edges : Count?
  max_degree : Count?
  usage : Usage
}

///|
struct CheckedDegree {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  direction : Direction
  usage : Usage
}

///|
fn diagnostic_rows(
  source : @decode.Cursor,
  fields : Array[(@row.FieldName, @contract.Contract?)],
  b : Budget,
) -> @carrier.Carrier raise Stop {
  if fields.length() > b.nodes {
    fail(source, BudgetExceeded)
  }
  spend(b, source, fields.length())
  b.nodes -= fields.length()
  for (name, _) in fields {
    charge(b, source, @row.reference_name(name))
  }
  let rows = match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=fields.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(rows) => rows
    Err(_) => fail(source, InvalidBody)
  }
  @carrier.relation(rows)
}

///|
pub fn check_graph_bounds(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedGraphBounds, Issue] {
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
    guard input is @carrier.GraphValue(graph) else {
      fail(
        source,
        if @carrier.kind(input) == @carrier.GraphKind {
          IncompleteGraph
        } else {
          WrongCarrier(@carrier.kind(input))
        },
      )
    }
    let body = decoded(
      @decode.closed_object(source, ["max_nodes", "max_edges", "max_degree"]),
    )
    if @decode.lookup(body, "max_nodes") is None &&
      @decode.lookup(body, "max_edges") is None &&
      @decode.lookup(body, "max_degree") is None {
      fail(source, InvalidBody)
    }
    let params : Map[String, @contract.Contract] = Map([])
    if parameters is Some(ds) {
      spend(b, source, @parameter.declaration_count(ds))
      for index in 0..<@parameter.declaration_count(ds) {
        let declaration = @parameter.declaration_at(ds, index).unwrap()
        charge(b, source, declaration.name)
        params[declaration.name] = declaration.parameter_type.contract
      }
    }
    let max_nodes = @decode.lookup(body, "max_nodes").map(at => {
      count(at, params, minimum=0L)
    })
    let max_edges = @decode.lookup(body, "max_edges").map(at => {
      count(at, params, minimum=0L)
    })
    let max_degree = @decode.lookup(body, "max_degree").map(at => {
      count(at, params, minimum=0L)
    })
    let text = @contract.primitive(StringType, nullable=false)
    let number = @contract.primitive(NumberType, nullable=false)
    let output = diagnostic_rows(
      source,
      [
        (@row.Unqualified("kind"), Some(text)),
        (
          @row.Unqualified("node_id"),
          Some(@contract.with_nullability(@carrier.graph_identity(graph), true)),
        ),
        (@row.Unqualified("actual"), Some(number)),
        (@row.Unqualified("max"), Some(number)),
      ],
      b,
    )
    Ok({
      source,
      input,
      output,
      max_nodes,
      max_edges,
      max_degree,
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
pub fn check_degree(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedDegree, Issue] {
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
    guard input is @carrier.GraphValue(graph) else {
      fail(
        source,
        if @carrier.kind(input) == @carrier.GraphKind {
          IncompleteGraph
        } else {
          WrongCarrier(@carrier.kind(input))
        },
      )
    }
    let body = decoded(@decode.closed_object(source, ["direction"]))
    let at = decoded(@decode.required(body, "direction"))
    let direction = match decoded(@decode.text(at)) {
      "in" => Incoming
      "out" => Outgoing
      "both" => Both
      _ => fail(at, InvalidBody)
    }
    let output = diagnostic_rows(
      source,
      [
        (@row.Unqualified("node"), Some(@carrier.graph_identity(graph))),
        (
          @row.Unqualified("degree"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      b,
    )
    Ok({
      source,
      input,
      output,
      direction,
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
pub fn graph_bounds_output(value : CheckedGraphBounds) -> @carrier.Carrier {
  value.output
}

///|
pub fn graph_bounds_source(value : CheckedGraphBounds) -> @decode.Cursor {
  value.source
}

///|
pub fn graph_bounds_input(value : CheckedGraphBounds) -> @carrier.Carrier {
  value.input
}

///|
pub fn graph_bounds_usage(value : CheckedGraphBounds) -> Usage {
  value.usage
}

///|
pub fn graph_bounds_thresholds(
  value : CheckedGraphBounds,
) -> (Count?, Count?, Count?) {
  (value.max_nodes, value.max_edges, value.max_degree)
}

///|
pub fn degree_output(value : CheckedDegree) -> @carrier.Carrier {
  value.output
}

///|
pub fn degree_source(value : CheckedDegree) -> @decode.Cursor {
  value.source
}

///|
pub fn degree_input(value : CheckedDegree) -> @carrier.Carrier {
  value.input
}

///|
pub fn degree_usage(value : CheckedDegree) -> Usage {
  value.usage
}

///|
pub fn degree_direction(value : CheckedDegree) -> Direction {
  value.direction
}
