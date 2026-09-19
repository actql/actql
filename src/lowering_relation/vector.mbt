///|
/// Checked VecA and vector-Bridge parameters retained for canonical emission.
/// Runtime layout and storage choices do not enter this view.
struct PreparedVector {
  node : PreparedNode
  params : PreparedVectorParams
}

///|
priv enum PreparedVectorParams {
  VectorBridgeParams(String, String)
  VectorNormalizeParams
  VectorScoreParams(@vector_checking.Metric, Array[Double])
  VectorPoolParams(Array[String], @vector.PoolMethod, String?, String?)
}

///|
/// Runtime score decision retained by checked lowering.
pub(all) enum PreparedVectorMetric {
  CosineScore
  DotScore
  L2Score
} derive(Eq, Debug)

///|
/// Resolved pooling reduction retained by checked lowering.
pub(all) enum PreparedVectorPoolMethod {
  PoolMean
  PoolSum
  PoolMax
} derive(Eq, Debug)

///|
/// Exact checked output Carrier for this prepared vector operation.
pub fn vector_output_carrier(value : PreparedVector) -> @carrier.Carrier {
  value.node.output_carrier
}

///|
/// Resolved score metric. Non-scoring vector operations return None.
pub fn vector_score_metric(value : PreparedVector) -> PreparedVectorMetric? {
  match value.params {
    VectorScoreParams(metric, _) =>
      Some(
        match metric {
          @vector_checking.Cosine => CosineScore
          @vector_checking.Dot => DotScore
          @vector_checking.L2 => L2Score
        },
      )
    _ => None
  }
}

///|
/// Number of resolved query components without copying their array.
pub fn vector_score_query_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorScoreParams(_, query) => Some(query.length())
    _ => None
  }
}

///|
/// One resolved query component in authored dimension order.
pub fn vector_score_query_at(value : PreparedVector, index : Int) -> Double? {
  match value.params {
    VectorScoreParams(_, query) => query.get(index)
    _ => None
  }
}

///|
/// Number of checked grouping fields in authored order.
pub fn vector_pool_group_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorPoolParams(groups, _, _, _) => Some(groups.length())
    _ => None
  }
}

///|
/// One checked grouping field without exposing mutable parameter storage.
pub fn vector_pool_group_at(value : PreparedVector, index : Int) -> String? {
  match value.params {
    VectorPoolParams(groups, _, _, _) => groups.get(index)
    _ => None
  }
}

///|
/// Checked pooling reduction for a pooling operation.
pub fn vector_pool_method(value : PreparedVector) -> PreparedVectorPoolMethod? {
  match value.params {
    VectorPoolParams(_, reduction, _, _) =>
      Some(
        match reduction {
          @vector.Mean => PoolMean
          @vector.Sum => PoolSum
          @vector.Max => PoolMax
        },
      )
    _ => None
  }
}

///|
/// Optional checked output identity alias.
pub fn vector_pool_output_id(value : PreparedVector) -> String? {
  match value.params {
    VectorPoolParams(_, _, output_id, _) => output_id
    _ => None
  }
}

///|
/// Optional authored vector role. Vectors input may omit this restatement.
pub fn vector_pool_vector_role(value : PreparedVector) -> String? {
  match value.params {
    VectorPoolParams(_, _, _, vector) => vector
    _ => None
  }
}

///|
pub(all) enum VectorIssue {
  InvalidVectorLimits
  InvalidVectorWiring
  VectorPreparationLimit
  MissingVectorParameter(String)
  InvalidVectorParameter(String)
} derive(Eq, Debug)

///|
fn checked_query_values(
  owner : BoundPrepared,
  checked : @vector.CheckedVector,
) -> Result[(Array[Double], Int, Int), VectorIssue] {
  guard @vector.query(checked) is Some(query) else {
    return Err(InvalidVectorWiring)
  }
  match @vector.query_parameter(query) {
    None => {
      let count = @vector.query_value_count(query).unwrap_or(0)
      let values = []
      for index in 0..<count {
        guard @vector.query_value_at(query, index) is Some(value) else {
          return Err(InvalidVectorWiring)
        }
        values.push(value)
      }
      Ok((values, 0, 0))
    }
    Some(name) => {
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingVectorParameter(name))
      }
      guard bound.value is @value.Array(items) else {
        return Err(InvalidVectorParameter(name))
      }
      let values = []
      for item in @value.elements(items) {
        guard item is @value.Number(value) else {
          return Err(InvalidVectorParameter(name))
        }
        values.push(value)
      }
      if values.is_empty() {
        return Err(InvalidVectorParameter(name))
      }
      Ok((values, 1, @utf8.encode(name).length()))
    }
  }
}

///|
fn prepare_vector_node(
  owner : BoundPrepared,
  node : PreparedNode,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedVector, Int, Int, Int), VectorIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidVectorLimits)
  }
  let (params, bindings, names, work) = match node.payload {
    VectorValue(checked) =>
      match @vector.operation(checked) {
        @vector.ToVectors => {
          guard @vector.output(checked) is @carrier.VectorValue(output) &&
            @carrier.vector_identity_count(output) == 1 &&
            @carrier.vector_identity_at(output, 0) is Some(identity) else {
            return Err(InvalidVectorWiring)
          }
          let id = @schema.reference_name(identity.name)
          let components = @schema.reference_name(
            @carrier.vector_components(output).name,
          )
          (
            VectorBridgeParams(id, components),
            2,
            @utf8.encode(id).length() + @utf8.encode(components).length(),
            2,
          )
        }
        @vector.NormalizeVectors => (VectorNormalizeParams, 0, 0, 0)
        @vector.ScoreVectors => {
          guard @vector.metric(checked) is Some(metric) else {
            return Err(InvalidVectorWiring)
          }
          let (values, used_bindings, used_names) = match
            checked_query_values(owner, checked) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          (
            VectorScoreParams(metric, values),
            used_bindings,
            used_names,
            values.length() + 2,
          )
        }
      }
    PoolValue(checked) => {
      let options = @vector.pooled_options(checked)
      let groups : Array[String] = []
      let mut used_names = 0
      for index in 0..<@vector.pool_group_count(options) {
        guard @vector.pool_group_at(options, index) is Some(field) else {
          return Err(InvalidVectorWiring)
        }
        let name = @schema.reference_name(field)
        groups.push(name)
        used_names += @utf8.encode(name).length()
      }
      let vector = match @vector.pool_vector(options) {
        Some(field) => {
          let name = @schema.reference_name(field)
          used_names += @utf8.encode(name).length()
          Some(name)
        }
        None => None
      }
      let output_id = @vector.pool_output_id(options)
      if output_id is Some(name) {
        used_names += @utf8.encode(name).length()
      }
      (
        VectorPoolParams(
          groups,
          @vector.pool_method(options),
          output_id,
          vector,
        ),
        0,
        used_names,
        groups.length() + 2,
      )
    }
    _ => return Err(InvalidVectorWiring)
  }
  if bindings > max_bindings || names > max_name_bytes || work > max_work {
    return Err(VectorPreparationLimit)
  }
  Ok(({ node, params, }, bindings, names, work))
}

///|
fn emit_vector_node(
  prepared : PreparedVector,
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
  match prepared.params {
    VectorBridgeParams(id, components) => {
      @encode.key(out, "id")
      @encode.string_value(out, id)
      @encode.key(out, "vector")
      @encode.string_value(out, components)
    }
    VectorNormalizeParams => ()
    VectorScoreParams(metric, query) => {
      @encode.key(out, "metric")
      @encode.string_value(
        out,
        match metric {
          @vector_checking.Cosine => "cosine"
          @vector_checking.Dot => "dot"
          @vector_checking.L2 => "l2"
        },
      )
      @encode.key(out, "query")
      @encode.begin_array(out)
      for value in query {
        @encode.number_value(out, value)
      }
      @encode.end_array(out)
    }
    VectorPoolParams(groups, reduction, output_id, vector) => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for group in groups {
        @encode.string_value(out, group)
      }
      @encode.end_array(out)
      @encode.key(out, "method")
      @encode.string_value(
        out,
        match reduction {
          @vector.Mean => "mean"
          @vector.Sum => "sum"
          @vector.Max => "max"
        },
      )
      if output_id is Some(name) {
        @encode.key(out, "output_id")
        @encode.string_value(out, name)
      }
      if vector is Some(name) {
        @encode.key(out, "vector")
        @encode.string_value(out, name)
      }
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
