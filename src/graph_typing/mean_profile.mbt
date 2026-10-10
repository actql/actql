///|
/// A finite sample list with current Graph domain/field alignment. It grants
/// neither physical execution nor permission to publish a partial mean.
struct CheckedMean {
  options : CheckedMeanOptions
  inputs : Array[@carrier.Carrier]
  alignment : Array[UnionFold]
  output : @carrier.Carrier
  usage : Usage
}

///|
pub(all) enum MeanObligation {
  AdmitMeanInputs
  PreserveMeanIdentities
  CheckMeanLabelsAndEndpoints
  ResolveMeanResources
  ApplyExactMeanSupport
  ApplyMeanPropertyStrategies
  CanonicalMeanOrder
} derive(Eq, Debug)

///|
fn mean_strategy_map(
  source : @decode.Cursor,
  properties : Array[MeanProperty],
  b : Budget,
) -> (Map[String, UnionPropertyStrategy], Map[String, Bool]) raise Stop {
  let strategies = Map([])
  let nullable_numbers = Map([])
  for property in properties {
    spend(b, source, 1)
    let name = property.name
    if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
      fail(source, InvalidName(name))
    }
    let key = @carrier.graph_name_identity(name)
    if strategies.contains(key) {
      fail(source, DuplicateConstructionField(name))
    }
    // Alignment must not perform the mean. Every runtime property policy
    // remains on the checked mean options, separate from structural typing.
    strategies[key] = UnionExactEqual
    if property.strategy is WeightedMean(_, _) {
      nullable_numbers[key] = true
    }
  }
  (strategies, nullable_numbers)
}

///|
fn require_mean_property_domain(
  source : @decode.Cursor,
  graph : @carrier.GraphDefinition,
  strategies : Map[String, UnionPropertyStrategy],
  edge~ : Bool,
  b : Budget,
) -> Unit raise Stop {
  let count = if edge {
    @carrier.graph_edge_count(graph)
  } else {
    @carrier.graph_node_count(graph)
  }
  for index in 0..<count {
    spend(b, source, 1)
    let definition = if edge {
      @carrier.graph_edge_element(@carrier.graph_edge_at(graph, index).unwrap())
    } else {
      @carrier.graph_node_at(graph, index).unwrap()
    }
    let properties = @carrier.graph_element_definition_properties(definition)
    for index in 0..<@carrier.field_count(properties) {
      spend(b, source, 1)
      let field = @carrier.field_at(properties, index).unwrap()
      let name = @row.reference_name(field.name)
      if !strategies.contains(@carrier.graph_name_identity(name)) {
        fail(source, InvalidPropertyStrategy(name))
      }
    }
  }
}

///|
/// Inputs are exactly the authored list in its original order, including
/// repeated names and zero weights. There is no implicit current Graph.
pub fn check_mean(
  source : @decode.Cursor,
  inputs : Array[@carrier.Carrier],
  limits : Limits,
) -> Result[CheckedMean, Issue] {
  let options = match check_mean_options(source, limits) {
    Ok(options) => options
    Err(issue) => return Err(issue)
  }
  try {
    if inputs.length() != options.names.length() {
      fail(source, InvalidBody)
    }
    let b : Budget = {
      limits,
      work: limits.max_work - options.usage.work,
      nodes: limits.max_nodes - options.usage.nodes,
      text: limits.max_text_bytes - options.usage.text_bytes,
    }
    let first = union_graph_definition(source, inputs[0])
    let (node_strategies, nullable_nodes) = mean_strategy_map(
      source,
      options.nodes,
      b,
    )
    let (edge_strategies, nullable_edges) = mean_strategy_map(
      source,
      options.edges,
      b,
    )
    require_mean_property_domain(source, first, node_strategies, edge=false, b)
    require_mean_property_domain(source, first, edge_strategies, edge=true, b)
    let alignment = []
    let mut output = inputs[0]
    // Including the first sample checks singleton lists and applies nullable
    // numeric output contracts even when only one sample was authored.
    for input in inputs {
      spend(b, source, 1)
      let joined = align_graph_domains(
        source,
        output,
        input,
        node_strategies,
        edge_strategies,
        b,
        nullable_nodes~,
        nullable_edges~,
        common_roles=true,
      )
      output = joined.output
      alignment.push(joined)
    }
    Ok({
      options,
      inputs: inputs.copy(),
      alignment,
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
pub fn mean_output(value : CheckedMean) -> @carrier.Carrier {
  value.output
}

///|
pub fn checked_mean_options(value : CheckedMean) -> CheckedMeanOptions {
  value.options
}

///|
pub fn mean_usage(value : CheckedMean) -> Usage {
  value.usage
}

///|
pub fn mean_input_at(value : CheckedMean, sample : Int) -> @carrier.Carrier? {
  value.inputs.get(sample)
}

///|
pub fn mean_definition_at(
  value : CheckedMean,
  sample : Int,
  definition : Int,
  edge~ : Bool,
) -> Int? {
  value.alignment
  .get(sample)
  .bind(joined => {
    (if edge { joined.edges } else { joined.nodes })
    .get(definition)
    .map(alignment => alignment.right)
  })
}

///|
pub fn mean_property_input_at(
  value : CheckedMean,
  sample : Int,
  definition : Int,
  property : Int,
  edge~ : Bool,
) -> Int? {
  value.alignment
  .get(sample)
  .bind(joined => {
    (if edge { joined.edges } else { joined.nodes })
    .get(definition)
    .bind(alignment => alignment.fields.get(property).map(field => field.right))
  })
}

///|
pub fn mean_pending_count(_ : CheckedMean) -> Int {
  7
}

///|
pub fn mean_pending_at(_ : CheckedMean, index : Int) -> MeanObligation? {
  match index {
    0 => Some(AdmitMeanInputs)
    1 => Some(PreserveMeanIdentities)
    2 => Some(CheckMeanLabelsAndEndpoints)
    3 => Some(ResolveMeanResources)
    4 => Some(ApplyExactMeanSupport)
    5 => Some(ApplyMeanPropertyStrategies)
    6 => Some(CanonicalMeanOrder)
    _ => None
  }
}
