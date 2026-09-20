///|
struct PreparedGraphBasic {
  node : PreparedNode
  params : PreparedGraphBasicParams
}

///|
pub(all) enum GraphBasicKind {
  NormalizeBasic
  DegreeIncomingBasic
  DegreeOutgoingBasic
  DegreeBothBasic
  ComponentsWeakBasic
  ComponentsStrongBasic
  BoundsBasic
} derive(Eq, Debug)

///|
pub fn graph_basic_kind(value : PreparedGraphBasic) -> GraphBasicKind {
  match value.params {
    NormalizeParams => NormalizeBasic
    DegreeParams(@graph.Incoming) => DegreeIncomingBasic
    DegreeParams(@graph.Outgoing) => DegreeOutgoingBasic
    DegreeParams(@graph.Both) => DegreeBothBasic
    ComponentParams(@graph.Weak, _) => ComponentsWeakBasic
    ComponentParams(@graph.Strong, _) => ComponentsStrongBasic
    BoundsParams(_, _, _) => BoundsBasic
  }
}

///|
pub fn graph_basic_output_schema(value : PreparedGraphBasic) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
pub fn graph_basic_bounds(
  value : PreparedGraphBasic,
) -> (Int64?, Int64?, Int64?)? {
  match value.params {
    BoundsParams(nodes, edges, degree) => Some((nodes, edges, degree))
    _ => None
  }
}

///|
pub fn graph_basic_component_max_output_rows(
  value : PreparedGraphBasic,
) -> Int64? {
  match value.params {
    ComponentParams(_, maximum) => maximum
    _ => None
  }
}

///|
priv enum PreparedGraphBasicParams {
  NormalizeParams
  DegreeParams(@graph.Direction)
  ComponentParams(@graph.ComponentKind, Int64?)
  BoundsParams(Int64?, Int64?, Int64?)
}

///|
pub(all) enum GraphBasicIssue {
  InvalidGraphBasicLimits
  InvalidGraphBasicWiring
  GraphBasicPreparationLimit
  MissingGraphBasicParameter(String)
  InvalidGraphBasicParameter(String)
} derive(Eq, Debug)

///|
fn prepare_graph_basic_node(
  owner : BoundPrepared,
  node : PreparedNode,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphBasic, Int, Int, Int), GraphBasicIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidGraphBasicLimits)
  }
  guard node.payload is BasicGraph(checked) else {
    return Err(InvalidGraphBasicWiring)
  }
  let mut used_bindings = 0
  let mut used_names = 0
  let mut used_work = 0
  let resolve_count = fn(
    value : @graph.Count,
    minimum : Int64,
  ) -> Result[Int64, GraphBasicIssue] {
    match value {
      @graph.Literal(value) =>
        if value >= minimum && value <= 9007199254740991L {
          Ok(value)
        } else {
          Err(InvalidGraphBasicParameter(""))
        }
      @graph.Parameter(name) => {
        let bytes = @utf8.encode(name).length()
        if used_bindings >= max_bindings ||
          bytes > max_name_bytes - used_names ||
          used_work >= max_work {
          return Err(GraphBasicPreparationLimit)
        }
        used_bindings += 1
        used_names += bytes
        used_work += 1
        guard parameter_value(owner, name) is Some(bound) else {
          return Err(MissingGraphBasicParameter(name))
        }
        guard bound.value is @value.Number(number) &&
          @scalar.read_safe_integer(number) is Some(value) &&
          value >= minimum else {
          return Err(InvalidGraphBasicParameter(name))
        }
        Ok(value)
      }
    }
  }
  let params = match (@graph.operation(checked), @graph.options(checked)) {
    (@graph.NormalizeGraph, @graph.Normalize) => NormalizeParams
    (@graph.Degree, @graph.DegreeOptions(direction)) => DegreeParams(direction)
    (@graph.Components, @graph.ComponentOptions(kind, max_output_rows~)) => {
      let maximum = match max_output_rows {
        None => None
        Some(value) =>
          match resolve_count(value, 1L) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
      }
      ComponentParams(kind, maximum)
    }
    (
      @graph.GraphBounds,
      @graph.BoundsOptions(max_nodes~, max_edges~, max_degree~),
    ) => {
      let nodes = match max_nodes {
        None => None
        Some(value) =>
          match resolve_count(value, 0L) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
      }
      let edges = match max_edges {
        None => None
        Some(value) =>
          match resolve_count(value, 0L) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
      }
      let degree = match max_degree {
        None => None
        Some(value) =>
          match resolve_count(value, 0L) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
      }
      BoundsParams(nodes, edges, degree)
    }
    _ => return Err(InvalidGraphBasicWiring)
  }
  Ok(({ node, params, }, used_bindings, used_names, used_work))
}

///|
fn emit_graph_basic_params(
  params : PreparedGraphBasicParams,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match params {
    NormalizeParams => ()
    DegreeParams(direction) => {
      @encode.key(out, "direction")
      @encode.string_value(
        out,
        match direction {
          @graph.Incoming => "in"
          @graph.Outgoing => "out"
          @graph.Both => "both"
        },
      )
    }
    ComponentParams(kind, maximum) => {
      @encode.key(out, "kind")
      @encode.string_value(
        out,
        match kind {
          @graph.Weak => "weak"
          @graph.Strong => "strong"
        },
      )
      if maximum is Some(value) {
        @encode.key(out, "max_output_rows")
        @encode.number_value(out, value.to_double())
      }
    }
    BoundsParams(nodes, edges, degree) => {
      if degree is Some(value) {
        @encode.key(out, "max_degree")
        @encode.number_value(out, value.to_double())
      }
      if edges is Some(value) {
        @encode.key(out, "max_edges")
        @encode.number_value(out, value.to_double())
      }
      if nodes is Some(value) {
        @encode.key(out, "max_nodes")
        @encode.number_value(out, value.to_double())
      }
    }
  }
  @encode.end_object(out)
}

///|
fn emit_graph_basic_node(
  prepared : PreparedGraphBasic,
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
  emit_graph_basic_params(prepared.params, out)
  @encode.end_object(out)
}
