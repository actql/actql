///|
struct PreparedGraphMean {
  node : PreparedNode
  options : @graph.CheckedMeanOptions
}

///|
pub(all) enum GraphMeanIssue {
  InvalidGraphMeanLimits
  InvalidGraphMeanWiring
  GraphMeanPreparationLimit
} derive(Eq, Debug)

///|
fn prepare_graph_mean_node(
  node : PreparedNode,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedGraphMean, Int, Int, Int), GraphMeanIssue] {
  if max_entries < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidGraphMeanLimits)
  }
  guard node.payload is GraphMeanValue(checked) else {
    return Err(InvalidGraphMeanWiring)
  }
  let options = @graph.mean_options(checked)
  let samples = @graph.mean_sample_count(options)
  let nodes = @graph.mean_property_count(options, @graph.Nodes)
  let edges = @graph.mean_property_count(options, @graph.Edges)
  if samples > max_entries ||
    nodes > max_entries - samples ||
    edges > max_entries - samples - nodes ||
    samples > max_work ||
    nodes > max_work - samples ||
    edges > max_work - samples - nodes {
    return Err(GraphMeanPreparationLimit)
  }
  let mut name_bytes = 0
  for entity in [@graph.Nodes, @graph.Edges] {
    for index in 0..<@graph.mean_property_count(options, entity) {
      let property = @graph.mean_property_at(options, entity, index).unwrap()
      let bytes = @utf8.encode(property.name).length()
      if bytes > max_name_bytes - name_bytes {
        return Err(GraphMeanPreparationLimit)
      }
      name_bytes += bytes
    }
  }
  let entries = samples + nodes + edges
  Ok(({ node, options, }, entries, name_bytes, entries))
}

///|
fn emit_graph_mean_strategy(
  strategy : @graph.MeanStrategy,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match strategy {
    @graph.EqualValues => @encode.string_value(out, "exact_equal")
    @graph.WeightedMean(missing, nulls) => {
      @encode.begin_object(out)
      @encode.key(out, "mean")
      @encode.begin_object(out)
      @encode.key(out, "missing")
      @encode.string_value(
        out,
        match missing {
          @graph.ExcludeMissing => "exclude"
          @graph.ZeroMissing => "zero"
        },
      )
      @encode.key(out, "nulls")
      @encode.string_value(
        out,
        match nulls {
          @graph.ExcludeNull => "exclude"
          @graph.ZeroNull => "zero"
          @graph.FailNull => "fail"
        },
      )
      @encode.end_object(out)
      @encode.end_object(out)
    }
  }
}

///|
fn emit_graph_mean_properties(
  options : @graph.CheckedMeanOptions,
  entity : @graph.EntityKind,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  for index in 0..<@graph.mean_property_count(options, entity) {
    let property = @graph.mean_property_at(options, entity, index).unwrap()
    @encode.key(out, property.name)
    emit_graph_mean_strategy(property.strategy, out)
  }
  @encode.end_object(out)
}

///|
fn emit_graph_mean_node(
  prepared : PreparedGraphMean,
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
  @encode.string_value(out, "SGA.mean_structural")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "weights")
  @encode.begin_array(out)
  for index in 0..<@graph.mean_sample_count(prepared.options) {
    @encode.number_value(
      out,
      @graph.mean_weight_at(prepared.options, index).unwrap(),
    )
  }
  @encode.end_array(out)
  @encode.key(out, "support")
  @encode.begin_object(out)
  @encode.key(out, "nodes")
  @encode.number_value(out, @graph.mean_support(prepared.options, @graph.Nodes))
  @encode.key(out, "edges")
  @encode.number_value(out, @graph.mean_support(prepared.options, @graph.Edges))
  @encode.end_object(out)
  @encode.key(out, "properties")
  @encode.begin_object(out)
  @encode.key(out, "nodes")
  emit_graph_mean_properties(prepared.options, @graph.Nodes, out)
  @encode.key(out, "edges")
  emit_graph_mean_properties(prepared.options, @graph.Edges, out)
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
