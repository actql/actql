///|
pub(all) enum MissingMeanValue {
  ExcludeMissing
  ZeroMissing
} derive(Eq, Debug)

///|
pub(all) enum NullMeanValue {
  ExcludeNull
  ZeroNull
  FailNull
} derive(Eq, Debug)

///|
pub(all) enum MeanStrategy {
  EqualValues
  WeightedMean(MissingMeanValue, NullMeanValue)
} derive(Eq, Debug)

///|
pub struct MeanProperty {
  name : String
  strategy : MeanStrategy
}

///|
struct CheckedMeanOptions {
  source : @decode.Cursor
  names : Array[String]
  weights : Array[Double]
  node_support : Double
  edge_support : Double
  nodes : Array[MeanProperty]
  edges : Array[MeanProperty]
  usage : Usage
}

///|
fn mean_strategies(
  b : Budget,
  source : @decode.Cursor,
) -> Array[MeanProperty] raise Stop {
  let object = decoded(@decode.open_object(source))
  let names = decoded(@decode.object_field_names(source))
  spend(b, source, names.length())
  let result : Array[MeanProperty] = []
  for name in names {
    let at = @decode.lookup(object, name).unwrap()
    let strategy = if @decode.view(at) is TextValue(_) {
      let s = decoded(@decode.text(at))
      if s != "exact_equal" {
        fail(at, InvalidPropertyStrategy(s))
      }
      EqualValues
    } else {
      let root = decoded(@decode.closed_object(at, ["mean"]))
      let body = decoded(@decode.required(root, "mean"))
      let body = decoded(@decode.closed_object(body, ["missing", "nulls"]))
      let missing_at = decoded(@decode.required(body, "missing"))
      let missing = match decoded(@decode.text(missing_at)) {
        "exclude" => ExcludeMissing
        "zero" => ZeroMissing
        s => fail(missing_at, InvalidPropertyStrategy(s))
      }
      let nulls_at = decoded(@decode.required(body, "nulls"))
      let nulls = match decoded(@decode.text(nulls_at)) {
        "exclude" => ExcludeNull
        "zero" => ZeroNull
        "fail" => FailNull
        s => fail(nulls_at, InvalidPropertyStrategy(s))
      }
      WeightedMean(missing, nulls)
    }
    result.push({ name, strategy, })
  }
  result.sort_by((a, z) => @canonical.compare_utf16(a.name, z.name))
  result
}

///|
/// Checks authored options only; this does not issue an executable Graph operation.
pub fn check_mean_options(
  source : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedMeanOptions, Issue] {
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
    let root = decoded(
      @decode.closed_object(source, ["with", "weights", "support", "properties"]),
    )
    let with_at = decoded(@decode.required(root, "with"))
    let inputs = decoded(@decode.elements(with_at))
    if inputs.is_empty() {
      fail(with_at, InvalidBody)
    }
    let names : Array[String] = []
    for at in inputs {
      let name = decoded(@decode.text(at))
      if name.is_empty() || @canonical.normalize_nfc_lf(name) != Ok(name) {
        fail(at, InvalidName(name))
      }
      names.push(name)
    }
    let weight_at = decoded(@decode.required(root, "weights"))
    let entries = decoded(@decode.elements(weight_at))
    if entries.length() != names.length() {
      fail(weight_at, InvalidWeight)
    }
    let weights : Array[Double] = []
    let mut positive = false
    for at in entries {
      let weight = decoded(@decode.finite_number(at))
      if weight < 0.0 {
        fail(at, InvalidWeight)
      }
      positive = positive || weight > 0.0
      weights.push(weight)
    }
    // Nonnegative finite samples have positive exact total iff one is positive.
    // Summing binary64 weights here would spuriously overflow for valid samples.
    if !positive {
      fail(weight_at, InvalidWeight)
    }
    let support = decoded(@decode.required(root, "support"))
    let support = decoded(@decode.closed_object(support, ["nodes", "edges"]))
    let thresholds : Array[Double] = []
    for name in ["nodes", "edges"] {
      let at = decoded(@decode.required(support, name))
      let threshold = decoded(@decode.finite_number(at))
      if threshold <= 0.0 || threshold > 1.0 {
        fail(at, InvalidBody)
      }
      thresholds.push(threshold)
    }
    let properties = decoded(@decode.required(root, "properties"))
    let properties = decoded(
      @decode.closed_object(properties, ["nodes", "edges"]),
    )
    let nodes = mean_strategies(
      b,
      decoded(@decode.required(properties, "nodes")),
    )
    let edges = mean_strategies(
      b,
      decoded(@decode.required(properties, "edges")),
    )
    Ok({
      source,
      names,
      weights,
      node_support: thresholds[0],
      edge_support: thresholds[1],
      nodes,
      edges,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn mean_input_names(c : CheckedMeanOptions) -> Array[String] {
  c.names.copy()
}

///|
pub fn mean_weights(c : CheckedMeanOptions) -> Array[Double] {
  c.weights.copy()
}

///|
/// Read one admitted sample weight without copying the sample list.
pub fn mean_weight_at(c : CheckedMeanOptions, index : Int) -> Double? {
  c.weights.get(index)
}

///|
pub fn mean_sample_count(c : CheckedMeanOptions) -> Int {
  c.weights.length()
}

///|
pub fn mean_property_count(c : CheckedMeanOptions, entity : EntityKind) -> Int {
  match entity {
    Nodes => c.nodes.length()
    Edges => c.edges.length()
  }
}

///|
/// Read an owned policy without copying the complete property map.
pub fn mean_property_at(
  c : CheckedMeanOptions,
  entity : EntityKind,
  index : Int,
) -> MeanProperty? {
  match entity {
    Nodes => c.nodes.get(index)
    Edges => c.edges.get(index)
  }
}

///|
pub fn mean_support(c : CheckedMeanOptions, entity : EntityKind) -> Double {
  match entity {
    Nodes => c.node_support
    Edges => c.edge_support
  }
}

///|
pub fn mean_properties(
  c : CheckedMeanOptions,
  entity : EntityKind,
) -> Array[MeanProperty] {
  match entity {
    Nodes => c.nodes.copy()
    Edges => c.edges.copy()
  }
}

///|
pub fn mean_options_usage(c : CheckedMeanOptions) -> Usage {
  c.usage
}

///|
pub fn mean_options_source(c : CheckedMeanOptions) -> @decode.Cursor {
  c.source
}
