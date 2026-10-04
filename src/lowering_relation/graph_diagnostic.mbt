///|
priv enum GraphDiagnosticChecked {
  Bounds(@graph.CheckedGraphBounds)
  Degree(@graph.CheckedDegree)
  Components(@graph.CheckedComponents)
}

///|
struct PreparedGraphDiagnostic {
  node : PreparedNode
  checked : GraphDiagnosticChecked
  node_limit : Int64?
  edge_limit : Int64?
  degree_limit : Int64?
  component_limit : Int64?
}

///|
pub(all) enum GraphDiagnosticKind {
  BoundsDiagnostic
  IncomingDegreeDiagnostic
  OutgoingDegreeDiagnostic
  TotalDegreeDiagnostic
  WeakComponentsDiagnostic
  StrongComponentsDiagnostic
} derive(Eq, Debug)

///|
pub fn graph_diagnostic_kind(
  value : PreparedGraphDiagnostic,
) -> GraphDiagnosticKind {
  match value.checked {
    Bounds(_) => BoundsDiagnostic
    Degree(checked) =>
      match @graph.degree_direction(checked) {
        @graph.Incoming => IncomingDegreeDiagnostic
        @graph.Outgoing => OutgoingDegreeDiagnostic
        @graph.Both => TotalDegreeDiagnostic
      }
    Components(checked) =>
      match @graph.components_kind(checked) {
        @graph.Weak => WeakComponentsDiagnostic
        @graph.Strong => StrongComponentsDiagnostic
      }
  }
}

///|
pub fn graph_diagnostic_bounds(
  value : PreparedGraphDiagnostic,
) -> (Int64?, Int64?, Int64?)? {
  match value.checked {
    Bounds(_) => Some((value.node_limit, value.edge_limit, value.degree_limit))
    Degree(_) => None
    Components(_) => None
  }
}

///|
pub fn graph_diagnostic_component_max_output_rows(
  value : PreparedGraphDiagnostic,
) -> Int64? {
  value.component_limit
}

///|
pub fn graph_diagnostic_output_schema(
  value : PreparedGraphDiagnostic,
) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
pub(all) enum GraphDiagnosticIssue {
  InvalidGraphDiagnosticLimits
  InvalidGraphDiagnosticWiring
  GraphDiagnosticPreparationLimit
  MissingGraphDiagnosticParameter(String)
  InvalidGraphDiagnosticParameter(String)
} derive(Eq, Debug)

///|
fn prepare_graph_diagnostic_node(
  owner : BoundPrepared,
  node : PreparedNode,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphDiagnostic, Int, Int, Int), GraphDiagnosticIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidGraphDiagnosticLimits)
  }
  let checked = match node.payload {
    GraphBoundsRows(value) => Bounds(value)
    GraphDegreeRows(value) => Degree(value)
    GraphComponentsRows(value) => Components(value)
    _ => return Err(InvalidGraphDiagnosticWiring)
  }
  if node.inputs.length() != 1 ||
    @carrier.kind(node.output_carrier) != @carrier.RelationKind ||
    node.output_schema is None {
    return Err(InvalidGraphDiagnosticWiring)
  }
  let mut bindings = 0
  let mut names = 0
  let mut work = 0
  let resolve = fn(
    bound : @graph.Count,
  ) -> Result[Int64, GraphDiagnosticIssue] {
    match bound {
      @graph.Literal(value) =>
        if value >= 0L && value <= 9007199254740991L {
          Ok(value)
        } else {
          Err(InvalidGraphDiagnosticParameter(""))
        }
      @graph.Parameter(name) => {
        let bytes = @utf8.encode(name).length()
        if bindings >= max_bindings ||
          bytes > max_name_bytes - names ||
          work >= max_work {
          return Err(GraphDiagnosticPreparationLimit)
        }
        bindings += 1
        names += bytes
        work += 1
        guard parameter_value(owner, name) is Some(value) else {
          return Err(MissingGraphDiagnosticParameter(name))
        }
        guard value.value is @value.Number(number) &&
          @scalar.read_safe_integer(number) is Some(integer) &&
          integer >= 0L else {
          return Err(InvalidGraphDiagnosticParameter(name))
        }
        Ok(integer)
      }
    }
  }
  let (node_limit, edge_limit, degree_limit, component_limit) = match checked {
    Bounds(value) => {
      let (nodes, edges, degree) = @graph.graph_bounds_thresholds(value)
      let result : Array[Int64?] = []
      for bound in [nodes, edges, degree] {
        match bound {
          None => result.push(None)
          Some(value) =>
            match resolve(value) {
              Ok(integer) => result.push(Some(integer))
              Err(issue) => return Err(issue)
            }
        }
      }
      (result[0], result[1], result[2], None)
    }
    Degree(_) => (None, None, None, None)
    Components(value) => {
      let maximum = match @graph.components_max_output_rows(value) {
        None => None
        Some(bound) =>
          match resolve(bound) {
            Ok(integer) if integer > 0L => Some(integer)
            Ok(_) =>
              return Err(InvalidGraphDiagnosticParameter("max_output_rows"))
            Err(issue) => return Err(issue)
          }
      }
      (None, None, None, maximum)
    }
  }
  Ok(
    (
      { node, checked, node_limit, edge_limit, degree_limit, component_limit, },
      bindings,
      names,
      work,
    ),
  )
}

///|
fn emit_graph_diagnostic_node(
  prepared : PreparedGraphDiagnostic,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  match graph_diagnostic_kind(prepared) {
    BoundsDiagnostic => {
      if prepared.degree_limit is Some(maximum) {
        @encode.key(out, "max_degree")
        @encode.number_value(out, maximum.to_double())
      }
      if prepared.edge_limit is Some(maximum) {
        @encode.key(out, "max_edges")
        @encode.number_value(out, maximum.to_double())
      }
      if prepared.node_limit is Some(maximum) {
        @encode.key(out, "max_nodes")
        @encode.number_value(out, maximum.to_double())
      }
    }
    WeakComponentsDiagnostic | StrongComponentsDiagnostic => {
      @encode.key(out, "kind")
      @encode.string_value(
        out,
        if graph_diagnostic_kind(prepared) == WeakComponentsDiagnostic {
          "weak"
        } else {
          "strong"
        },
      )
      if prepared.component_limit is Some(maximum) {
        @encode.key(out, "max_output_rows")
        @encode.number_value(out, maximum.to_double())
      }
    }
    direction => {
      @encode.key(out, "direction")
      @encode.string_value(
        out,
        match direction {
          IncomingDegreeDiagnostic => "in"
          OutgoingDegreeDiagnostic => "out"
          TotalDegreeDiagnostic => "both"
          BoundsDiagnostic => "both"
          WeakComponentsDiagnostic | StrongComponentsDiagnostic => "both"
        },
      )
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
