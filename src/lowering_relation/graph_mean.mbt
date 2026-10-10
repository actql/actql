///|
struct PreparedGraphMean {
  node : PreparedNode
  checked : @graph.CheckedMean
}

///|
pub(all) enum GraphMeanIssue {
  InvalidGraphMeanWiring
} derive(Eq, Debug)

///|
fn prepare_graph_mean_node(
  node : PreparedNode,
) -> Result[PreparedGraphMean, GraphMeanIssue] {
  guard node.payload is GraphMeanValue(checked) &&
    node.inputs.length() ==
    @graph.mean_sample_count(@graph.checked_mean_options(checked)) &&
    node.inputs.length() > 0 &&
    node.output_schema is None &&
    node.output_carrier is @carrier.GraphValue(_) else {
    return Err(InvalidGraphMeanWiring)
  }
  Ok({ node, checked, })
}

///|
pub fn graph_mean_checked(value : PreparedGraphMean) -> @graph.CheckedMean {
  value.checked
}

///|
fn emit_graph_mean_node(
  value : PreparedGraphMean,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let options = @graph.checked_mean_options(value.checked)
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, value.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in value.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(value.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "weights")
  @encode.begin_array(out)
  for index in 0..<value.node.inputs.length() {
    @encode.number_value(out, @graph.mean_weight_at(options, index).unwrap())
  }
  @encode.end_array(out)
  @encode.key(out, "support")
  @encode.begin_object(out)
  for entity in [@graph.Nodes, @graph.Edges] {
    @encode.key(out, if entity == @graph.Nodes { "nodes" } else { "edges" })
    @encode.number_value(out, @graph.mean_support(options, entity))
  }
  @encode.end_object(out)
  @encode.key(out, "properties")
  @encode.begin_object(out)
  for entity in [@graph.Nodes, @graph.Edges] {
    @encode.key(out, if entity == @graph.Nodes { "nodes" } else { "edges" })
    @encode.begin_object(out)
    let mut index = 0
    while @graph.mean_property_at(options, entity, index) is Some(property) {
      index += 1
      @encode.key(out, property.name)
      match property.strategy {
        @graph.EqualValues => @encode.string_value(out, "exact_equal")
        @graph.WeightedMean(missing, nulls) => {
          @encode.begin_object(out)
          @encode.key(out, "mean")
          @encode.begin_object(out)
          @encode.key(out, "missing")
          @encode.string_value(
            out,
            if missing == @graph.ExcludeMissing {
              "exclude"
            } else {
              "zero"
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
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
