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
/// Checks source options only; graph contracts and property coverage are checked separately.
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

///|
pub(all) enum MeanObligation {
  AdmitEveryMeanSample
  CompareExactRationalSupport
  RetainSupportedNodesBeforeEdges
  RequirePositiveWeightLabelAgreement
  ApplyEveryMeanPropertyPolicy
  RoundExactWeightedMeansOnce
  RejectNonfiniteMeanResults
  CanonicalMeanIdentityOrder
  PreserveMeanObservationAndPolicy
  ResolveMeanResources
  ResolveMeanProfile
} derive(Eq, Debug)

///|
struct CheckedMean {
  options : CheckedMeanOptions
  output : @carrier.Carrier
  usage : Usage
}

///|
fn mean_output_properties(
  b : Budget,
  source : @decode.Cursor,
  common : @row.Schema,
  strategies : Array[MeanProperty],
) -> @carrier.Knowledge raise Stop {
  let object = decoded(@decode.open_object(source))
  let properties = @carrier.typed_rows(common)
  spend(b, source, strategies.length() + @carrier.field_count(properties))
  if strategies.length() != @carrier.field_count(properties) {
    fail(source, InvalidBody)
  }
  let output : Array[(@row.FieldName, @contract.Contract?)] = []
  for p in strategies {
    let at = @decode.lookup(object, p.name).unwrap()
    let c = match @carrier.lookup(properties, Unqualified(p.name)) {
      Present({ contract: Some(c), .. }) => c
      _ => fail(at, UnknownMergeProperty(p.name))
    }
    let c = match p.strategy {
      EqualValues => c
      WeightedMean(_, _) => {
        guard c.shape is @contract.Number else {
          fail(at, IncompatiblePropertyStrategy(p.name))
        }
        if b.nodes <= 0 {
          fail(at, BudgetExceeded)
        }
        b.nodes -= 1
        @contract.with_nullability(c, true)
      }
    }
    charge(b, at, p.name)
    output.push((Unqualified(p.name), Some(c)))
  }
  match
    @carrier.rows(
      output,
      field_set=Closed,
      max_fields=output.length(),
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(rows) => rows
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
pub fn check_mean(
  source : @decode.Cursor,
  inputs : Array[@carrier.Carrier],
  limits : Limits,
) -> Result[CheckedMean, Issue] {
  try {
    let options = match check_mean_options(source, limits) {
      Ok(c) => c
      Err(e) => raise Stop(e)
    }
    let b : Budget = {
      limits,
      work: limits.max_work - options.usage.work,
      nodes: limits.max_nodes - options.usage.nodes,
      text: limits.max_text_bytes - options.usage.text_bytes,
    }
    let root = decoded(@decode.open_object(source))
    let with_at = decoded(@decode.required(root, "with"))
    if inputs.length() != options.names.length() {
      fail(with_at, InvalidBody)
    }
    let occurrences = decoded(@decode.elements(with_at))
    let mut node_schema : @row.Schema? = None
    let mut edge_schema : @row.Schema? = None
    let mut identity : @row.Schema? = None
    let mut label_type : @row.Schema? = None
    let mut all_label_types = true
    let mut all_labels = true
    let labels : Array[String] = []
    let seen : Map[String, Bool] = Map([])
    let mut names : @carrier.GraphRowNames? = None
    for i in 0..<inputs.length() {
      let at = occurrences[i]
      spend(b, at, 1)
      let g = match inputs[i] {
        @carrier.GraphValue(g) => {
          require_legacy_profile(g, at)
          g
        }
        @carrier.Opaque(GraphKind) => fail(at, IncompleteGraph)
        v => fail(at, WrongCarrier(@carrier.kind(v)))
      }
      let nodes = match
        @carrier.complete_schema(@carrier.graph_node_properties(g)) {
        Some(s) => s
        None => fail(at, IncompleteGraph)
      }
      let edges = match
        @carrier.complete_schema(@carrier.graph_edge_properties(g)) {
        Some(s) => s
        None => fail(at, IncompleteGraph)
      }
      node_schema = Some(
        align_domains(b, at, node_schema.unwrap_or(nodes), nodes),
      )
      edge_schema = Some(
        align_domains(b, at, edge_schema.unwrap_or(edges), edges),
      )
      let id = singleton_schema(@carrier.graph_identity(g))
      identity = Some(align_domains(b, at, identity.unwrap_or(id), id))
      match @carrier.graph_label_contract(g) {
        Some(c) => {
          let s = singleton_schema(c)
          label_type = Some(align_domains(b, at, label_type.unwrap_or(s), s))
        }
        None => all_label_types = false
      }
      let next_names = @carrier.graph_names(g)
      if i == 0 {
        names = next_names
      } else {
        match (names, next_names) {
          (Some(a), Some(z)) =>
            if @carrier.graph_row_fields(a) != @carrier.graph_row_fields(z) {
              names = None
            }
          _ => names = None
        }
      }
      // Zero-weight samples still participate in all contract checks above.
      // Only positive samples can contribute output label-domain values.
      if @carrier.graph_label_count(g) is Some(n) {
        spend(b, at, n)
        for j in 0..<n {
          let label = @carrier.graph_label_at(g, j).unwrap()
          charge(b, at, label)
          if options.weights[i] > 0.0 && !seen.contains(label) {
            seen[label] = true
            labels.push(label)
          }
        }
      } else if options.weights[i] > 0.0 {
        all_labels = false
      }
    }
    let properties = decoded(
      @decode.open_object(decoded(@decode.required(root, "properties"))),
    )
    let nodes = mean_output_properties(
      b,
      decoded(@decode.required(properties, "nodes")),
      node_schema.unwrap(),
      options.nodes,
    )
    let edges = mean_output_properties(
      b,
      decoded(@decode.required(properties, "edges")),
      edge_schema.unwrap(),
      options.edges,
    )
    let label_contract = if all_label_types {
      label_type.map(s => @row.lookup(s, Unqualified("value")).unwrap())
    } else {
      None
    }
    let output = match
      @carrier.graph(
        @row.lookup(identity.unwrap(), Unqualified("value")).unwrap(),
        nodes,
        edges,
        labels=if all_labels { Some(labels) } else { None },
        max_labels=labels.length(),
        max_label_bytes=limits.max_text_bytes,
        row_names=names,
        label_contract~,
      ) {
      Ok(c) => c
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      options,
      output,
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
pub fn mean_output(c : CheckedMean) -> @carrier.Carrier {
  c.output
}

///|
pub fn mean_options(c : CheckedMean) -> CheckedMeanOptions {
  c.options
}

///|
pub fn mean_usage(c : CheckedMean) -> Usage {
  c.usage
}

///|
pub fn mean_pending(_c : CheckedMean) -> Array[MeanObligation] {
  let out = []
  for i in 0..<mean_pending_count(_c) {
    out.push(mean_pending_at(_c, i).unwrap())
  }
  out
}

///|
/// O(1), without materializing the obligation array.
pub fn mean_pending_count(_c : CheckedMean) -> Int {
  11
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn mean_pending_at(_c : CheckedMean, index : Int) -> MeanObligation? {
  match index {
    0 => Some(AdmitEveryMeanSample)
    1 => Some(CompareExactRationalSupport)
    2 => Some(RetainSupportedNodesBeforeEdges)
    3 => Some(RequirePositiveWeightLabelAgreement)
    4 => Some(ApplyEveryMeanPropertyPolicy)
    5 => Some(RoundExactWeightedMeansOnce)
    6 => Some(RejectNonfiniteMeanResults)
    7 => Some(CanonicalMeanIdentityOrder)
    8 => Some(PreserveMeanObservationAndPolicy)
    9 => Some(ResolveMeanResources)
    10 => Some(ResolveMeanProfile)
    _ => None
  }
}
