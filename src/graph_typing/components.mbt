///|
pub(all) enum ComponentKind {
  Weak
  Strong
} derive(Eq, Debug)

///|
struct CheckedComponents {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  kind : ComponentKind
  max_output_rows : Count?
  usage : Usage
}

///|
pub(all) enum ComponentsObligation {
  AdmitComponentGraph
  EnforceComponentInputNodes
  ResolveComponentResources
  EnforceComponentOutputRows
  EnforceComponentAuthorGuard
  BindComponentAuthorGuard(String)
} derive(Eq, Debug)

///|
pub fn check_components(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedComponents, Issue] {
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
      @decode.closed_object(source, ["kind", "max_output_rows"]),
    )
    let at = decoded(@decode.required(body, "kind"))
    let kind = match decoded(@decode.text(at)) {
      "weak" => Weak
      "strong" => Strong
      _ => fail(at, InvalidBody)
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
    let max_output_rows = @decode.lookup(body, "max_output_rows").map(at => {
      count(at, params)
    })
    let identity = @carrier.graph_identity(graph)
    let size = @contract.primitive(NumberType, nullable=false)
    let output = diagnostic_rows(
      source,
      [
        (@row.Unqualified("node_id"), Some(identity)),
        (@row.Unqualified("component_id"), Some(identity)),
        (@row.Unqualified("component_size"), Some(size)),
      ],
      b,
    )
    Ok({
      source,
      input,
      output,
      kind,
      max_output_rows,
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
pub fn components_source(value : CheckedComponents) -> @decode.Cursor {
  value.source
}

///|
pub fn components_input(value : CheckedComponents) -> @carrier.Carrier {
  value.input
}

///|
pub fn components_output(value : CheckedComponents) -> @carrier.Carrier {
  value.output
}

///|
pub fn components_kind(value : CheckedComponents) -> ComponentKind {
  value.kind
}

///|
pub fn components_max_output_rows(value : CheckedComponents) -> Count? {
  value.max_output_rows
}

///|
pub fn components_usage(value : CheckedComponents) -> Usage {
  value.usage
}

///|
pub fn components_pending_count(value : CheckedComponents) -> Int {
  let mut count = 4
  if value.max_output_rows is Some(_) {
    count += 1
  }
  if value.max_output_rows is Some(Parameter(_)) {
    count += 1
  }
  count
}

///|
pub fn components_pending_at(
  value : CheckedComponents,
  index : Int,
) -> ComponentsObligation? {
  match index {
    0 => Some(AdmitComponentGraph)
    1 => Some(EnforceComponentInputNodes)
    2 => Some(ResolveComponentResources)
    3 => Some(EnforceComponentOutputRows)
    4 if value.max_output_rows is Some(_) => Some(EnforceComponentAuthorGuard)
    5 =>
      match value.max_output_rows {
        Some(Parameter(name)) => Some(BindComponentAuthorGuard(name))
        _ => None
      }
    _ => None
  }
}
