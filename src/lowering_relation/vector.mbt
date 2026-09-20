///|
/// Checked VecA and vector-Bridge parameters retained for canonical emission.
/// Runtime layout and storage choices do not enter this view.
struct PreparedVector {
  node : PreparedNode
  step : Int
  params : PreparedVectorParams
  expansion : Array[PreparedVectorExpansionNode]
}

///|
/// One node in a registered finite vector-operation expansion.
priv struct PreparedVectorExpansionNode {
  role : String
  operation : String
  inputs : Int
  source_node : Bool
}

///|
priv struct PreparedVectorBridgeRoles {
  identity : String
  vector : String
}

///|
pub(all) enum PreparedVectorRankingPolicy {
  RankingMaximum
  RankingWeightedSum(Double, Double)
  RankingRrf(Double, Array[Double], Double)
}

///|
priv struct PreparedRankingScoreContract {
  domain : String
  normalization : String
  minimum : Double
  maximum : Double
}

///|
priv struct PreparedRankingParams {
  by : Array[String]
  candidate : String
  score : String?
  rank : String?
  policy : PreparedVectorRankingPolicy
  contract : PreparedRankingScoreContract?
  tie_break : Array[String]?
  k : Int64
}

///|
fn vector_generated_role_id(step : Int, role : String) -> String {
  "vector_" + role + "_" + step.to_string()
}

///|
fn prepare_pool_expansion(
  checked : @vector.CheckedPool,
) -> Array[PreparedVectorExpansionNode] {
  let nodes : Array[PreparedVectorExpansionNode] = []
  if @vector.pool_key_declaration(checked) is Some(_) {
    if @vector.pool_encodes_member_key(checked) {
      nodes.push({
        role: "member_identity",
        operation: "REL.derive",
        inputs: 1,
        source_node: false,
      })
    }
    nodes.push({
      role: "members",
      operation: "BRIDGE.rows.to_vectors",
      inputs: 1,
      source_node: false,
    })
  }
  nodes.push({ role: "", operation: "VEC.pool", inputs: 1, source_node: true, })
  nodes
}

///|
fn nearest_input_requires_bridge(input : @vector.NearestInput) -> Bool {
  match @vector.nearest_input_source(input) {
    @evidence.KeySource(_) => true
    @evidence.CarrierSource(carrier) =>
      @carrier.kind(carrier) == @carrier.RelationKind
  }
}

///|
fn prepare_nearest_expansion(
  checked : @vector.CheckedNearest,
) -> Array[PreparedVectorExpansionNode] {
  let pair = @vector.nearest_pair(checked)
  let nodes : Array[PreparedVectorExpansionNode] = []
  for
    (side, role) in [
      (@evidence.Candidates, "candidates"),
      (@evidence.Queries, "queries"),
    ] {
    if nearest_input_requires_bridge(@vector.nearest_pair_input(pair, side)) {
      nodes.push({
        role,
        operation: "BRIDGE.rows.to_vectors",
        inputs: 1,
        source_node: false,
      })
    }
  }
  nodes.push({
    role: "",
    operation: "VEC.knn_join",
    inputs: 2,
    source_node: true,
  })
  nodes
}

///|
fn vector_expansion_reference_count(
  expansion : Array[PreparedVectorExpansionNode],
) -> Int {
  let mut count = 0
  for node in expansion {
    count += node.inputs
  }
  count
}

///|
priv enum PreparedVectorParams {
  VectorBridgeParams(String, String)
  VectorNormalizeParams
  VectorScoreParams(@vector_checking.Metric, Array[Double])
  VectorNearestParams(
    @vector_checking.Metric,
    Int64,
    PreparedVectorBridgeRoles?,
    PreparedVectorBridgeRoles?
  )
  VectorPoolParams(
    Array[String],
    @vector.PoolMethod,
    String?,
    String?,
    Array[String],
    Bool
  )
  VectorRankingParams(PreparedRankingParams)
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
/// Resolved exact-nearest metric. Other vector operations return None.
pub fn vector_nearest_metric(value : PreparedVector) -> PreparedVectorMetric? {
  match value.params {
    VectorNearestParams(metric, _, _, _) =>
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
/// Positive checked top-k bound retained without source re-interpretation.
pub fn vector_nearest_k(value : PreparedVector) -> Int64? {
  match value.params {
    VectorNearestParams(_, k, _, _) => Some(k)
    _ => None
  }
}

///|
/// Whether one exact input side needs the registered Relation bridge.
pub fn vector_nearest_requires_bridge(
  value : PreparedVector,
  side : @vector.NearestSide,
) -> Bool? {
  match value.params {
    VectorNearestParams(_, _, candidates, queries) =>
      Some(
        match side {
          @evidence.Candidates => candidates is Some(_)
          @evidence.Queries => queries is Some(_)
        },
      )
    _ => None
  }
}

///|
/// Checked vector contract for one exact nearest input when statically known.
pub fn vector_nearest_input_vectors(
  value : PreparedVector,
  side : @vector.NearestSide,
) -> @carrier.Vectors? {
  guard value.node.payload is NearestValue(checked) else { return None }
  @vector.nearest_input_vectors(
    @vector.nearest_pair_input(@vector.nearest_pair(checked), side),
  )
}

///|
/// Number of checked grouping fields in authored order.
pub fn vector_pool_group_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorPoolParams(groups, _, _, _, _, _) => Some(groups.length())
    _ => None
  }
}

///|
/// One checked grouping field without exposing mutable parameter storage.
pub fn vector_pool_group_at(value : PreparedVector, index : Int) -> String? {
  match value.params {
    VectorPoolParams(groups, _, _, _, _, _) => groups.get(index)
    _ => None
  }
}

///|
/// Checked pooling reduction for a pooling operation.
pub fn vector_pool_method(value : PreparedVector) -> PreparedVectorPoolMethod? {
  match value.params {
    VectorPoolParams(_, reduction, _, _, _, _) =>
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
    VectorPoolParams(_, _, output_id, _, _, _) => output_id
    _ => None
  }
}

///|
/// Optional authored vector role. Vectors input may omit this restatement.
pub fn vector_pool_vector_role(value : PreparedVector) -> String? {
  match value.params {
    VectorPoolParams(_, _, _, vector, _, _) => vector
    _ => None
  }
}

///|
/// Number of retained member-identity fields in canonical key order.
pub fn vector_pool_identity_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorPoolParams(_, _, _, _, identities, _) => Some(identities.length())
    _ => None
  }
}

///|
/// One retained member-identity field without exposing mutable storage.
pub fn vector_pool_identity_at(value : PreparedVector, index : Int) -> String? {
  match value.params {
    VectorPoolParams(_, _, _, _, identities, _) => identities.get(index)
    _ => None
  }
}

///|
/// Whether Relation input requires the registered composite-key encoding.
pub fn vector_pool_encodes_member_identity(value : PreparedVector) -> Bool? {
  match value.params {
    VectorPoolParams(_, _, _, _, _, encoded) => Some(encoded)
    _ => None
  }
}

///|
/// Exact intermediate Vectors contract selected by checked Relation pooling.
/// Direct Vectors pooling returns the operation input contract instead.
pub fn vector_pool_member_vectors(value : PreparedVector) -> @carrier.Vectors? {
  match value.node.payload {
    PoolValue(checked) => Some(@vector.pool_member_vectors(checked))
    _ => None
  }
}

///|
pub fn vector_ranking_input_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorRankingParams(_) => Some(value.node.inputs.length())
    _ => None
  }
}

///|
pub fn vector_ranking_by_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorRankingParams(ranking) => Some(ranking.by.length())
    _ => None
  }
}

///|
pub fn vector_ranking_by_at(value : PreparedVector, index : Int) -> String? {
  match value.params {
    VectorRankingParams(ranking) => ranking.by.get(index)
    _ => None
  }
}

///|
pub fn vector_ranking_candidate(value : PreparedVector) -> String? {
  match value.params {
    VectorRankingParams(ranking) => Some(ranking.candidate)
    _ => None
  }
}

///|
pub fn vector_ranking_score(value : PreparedVector) -> String? {
  match value.params {
    VectorRankingParams(ranking) => ranking.score
    _ => None
  }
}

///|
pub fn vector_ranking_rank(value : PreparedVector) -> String? {
  match value.params {
    VectorRankingParams(ranking) => ranking.rank
    _ => None
  }
}

///|
pub fn vector_ranking_policy(
  value : PreparedVector,
) -> PreparedVectorRankingPolicy? {
  match value.params {
    VectorRankingParams(ranking) =>
      Some(
        match ranking.policy {
          RankingMaximum => RankingMaximum
          RankingWeightedSum(left, right) => RankingWeightedSum(left, right)
          RankingRrf(rank_constant, weights, rank_window) =>
            RankingRrf(rank_constant, weights.copy(), rank_window)
        },
      )
    _ => None
  }
}

///|
pub fn vector_ranking_k(value : PreparedVector) -> Int64? {
  match value.params {
    VectorRankingParams(ranking) => Some(ranking.k)
    _ => None
  }
}

///|
pub fn vector_ranking_score_domain(value : PreparedVector) -> String? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.contract.map(contract => contract.domain)
    _ => None
  }
}

///|
pub fn vector_ranking_score_normalization(value : PreparedVector) -> String? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.contract.map(contract => contract.normalization)
    _ => None
  }
}

///|
pub fn vector_ranking_score_minimum(value : PreparedVector) -> Double? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.contract.map(contract => contract.minimum)
    _ => None
  }
}

///|
pub fn vector_ranking_score_maximum(value : PreparedVector) -> Double? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.contract.map(contract => contract.maximum)
    _ => None
  }
}

///|
pub fn vector_ranking_tie_break_count(value : PreparedVector) -> Int? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.tie_break.map(fields => fields.length())
    _ => None
  }
}

///|
pub fn vector_ranking_tie_break_at(
  value : PreparedVector,
  index : Int,
) -> String? {
  match value.params {
    VectorRankingParams(ranking) =>
      ranking.tie_break.bind(fields => fields.get(index))
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
fn checked_nearest_bridge_roles(
  input : @vector.NearestInput,
) -> Result[(PreparedVectorBridgeRoles?, Int, Int), VectorIssue] {
  if !nearest_input_requires_bridge(input) {
    return Ok((None, 0, 0))
  }
  guard @vector.nearest_input_vectors(input) is Some(vectors) &&
    @carrier.vector_identity_count(vectors) == 1 &&
    @carrier.vector_identity_at(vectors, 0) is Some(identity) else {
    return Err(InvalidVectorWiring)
  }
  let identity = @schema.reference_name(identity.name)
  let vector = @schema.reference_name(@carrier.vector_components(vectors).name)
  Ok(
    (
      Some({ identity, vector, }),
      @utf8.encode(identity).length() + @utf8.encode(vector).length(),
      2,
    ),
  )
}

///|
fn checked_ranking_params(
  checked : @vector.CheckedRanking,
) -> Result[(PreparedRankingParams, Int, Int), VectorIssue] {
  let options = @vector.merged_ranking_options(checked)
  let by : Array[String] = []
  let mut names = 0
  for index in 0..<@vector.ranking_by_count(options) {
    guard @vector.ranking_by_at(options, index) is Some(field) else {
      return Err(InvalidVectorWiring)
    }
    let name = @schema.reference_name(field)
    by.push(name)
    names += @utf8.encode(name).length()
  }
  let candidate = @schema.reference_name(@vector.ranking_candidate(options))
  names += @utf8.encode(candidate).length()
  let score = @vector.ranking_score(options).map(field => {
    let name = @schema.reference_name(field)
    names += @utf8.encode(name).length()
    name
  })
  let rank = @vector.ranking_rank(options).map(field => {
    let name = @schema.reference_name(field)
    names += @utf8.encode(name).length()
    name
  })
  let tie_break = match @vector.ranking_tie_break_count(options) {
    None => None
    Some(count) => {
      let fields : Array[String] = []
      for index in 0..<count {
        guard @vector.ranking_tie_break_at(options, index) is Some(field) else {
          return Err(InvalidVectorWiring)
        }
        let name = @schema.reference_name(field)
        fields.push(name)
        names += @utf8.encode(name).length()
      }
      Some(fields)
    }
  }
  let contract = @vector.ranking_score_contract(options).map(value => {
    let domain = @vector.score_contract_domain(value)
    let normalization = @vector.score_contract_normalization(value)
    names += @utf8.encode(domain).length()
    names += @utf8.encode(normalization).length()
    {
      domain,
      normalization,
      minimum: @vector.score_contract_minimum(value),
      maximum: @vector.score_contract_maximum(value),
    }
  })
  let policy = match @vector.ranking_policy_kind(options) {
    @vector.MaximumPolicy => RankingMaximum
    @vector.WeightedSumPolicy => {
      guard @vector.ranking_weight_at(options, 0) is Some(left) &&
        @vector.ranking_weight_at(options, 1) is Some(right) else {
        return Err(InvalidVectorWiring)
      }
      RankingWeightedSum(left, right)
    }
    @vector.ReciprocalRankPolicy => {
      guard @vector.ranking_rank_constant(options) is Some(rank_constant) &&
        @vector.ranking_rank_window(options) is Some(rank_window) else {
        return Err(InvalidVectorWiring)
      }
      let weights : Array[Double] = []
      for index in 0..<@vector.ranking_weight_count(options) {
        guard @vector.ranking_weight_at(options, index) is Some(weight) else {
          return Err(InvalidVectorWiring)
        }
        weights.push(weight)
      }
      RankingRrf(rank_constant, weights, rank_window)
    }
  }
  let input_count = @vector.merged_ranking_input_count(checked)
  if input_count < 2 {
    return Err(InvalidVectorWiring)
  }
  let work = by.length() +
    input_count +
    @vector.ranking_weight_count(options) +
    tie_break.map(fields => fields.length()).unwrap_or(0) +
    6
  Ok(
    (
      {
        by,
        candidate,
        score,
        rank,
        policy,
        contract,
        tie_break,
        k: @vector.ranking_k(options).to_int64(),
      },
      names,
      work,
    ),
  )
}

///|
fn prepare_vector_node(
  owner : BoundPrepared,
  step : Int,
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
    NearestValue(checked) => {
      let pair = @vector.nearest_pair(checked)
      let options = @vector.nearest_pair_options(pair)
      let (candidate, candidate_names, candidate_work) = match
        checked_nearest_bridge_roles(
          @vector.nearest_pair_input(pair, @evidence.Candidates),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let (query, query_names, query_work) = match
        checked_nearest_bridge_roles(
          @vector.nearest_pair_input(pair, @evidence.Queries),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      (
        VectorNearestParams(
          @vector.nearest_metric(options),
          @vector.nearest_k(options),
          candidate,
          query,
        ),
        0,
        candidate_names + query_names,
        candidate_work + query_work + 3,
      )
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
      let identities : Array[String] = []
      if @vector.pool_key_declaration(checked) is Some(key) {
        for index in 0..<@evidence.key_field_count(key) {
          guard @evidence.key_field_at(key, index) is Some(field) else {
            return Err(InvalidVectorWiring)
          }
          let name = @schema.reference_name(field.name)
          identities.push(name)
          used_names += @utf8.encode(name).length()
        }
      }
      (
        VectorPoolParams(
          groups,
          @vector.pool_method(options),
          output_id,
          vector,
          identities,
          @vector.pool_encodes_member_key(checked),
        ),
        0,
        used_names,
        groups.length() + identities.length() * 4 + 2,
      )
    }
    RankingValue(checked) => {
      let (params, used_names, used_work) = match
        checked_ranking_params(checked) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      (VectorRankingParams(params), 0, used_names, used_work)
    }
    _ => return Err(InvalidVectorWiring)
  }
  if bindings > max_bindings || names > max_name_bytes || work > max_work {
    return Err(VectorPreparationLimit)
  }
  let expansion = match node.vector_expansion {
    Some(expansion) => expansion
    None =>
      if node.payload is VectorValue(_) || node.payload is RankingValue(_) {
        []
      } else {
        return Err(InvalidVectorWiring)
      }
  }
  Ok(({ node, step, params, expansion, }, bindings, names, work))
}

///|
fn emit_vector_operation(
  prepared : PreparedVector,
  inputs : Array[String],
  include_pool_vector : Bool,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in inputs {
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
    VectorNearestParams(metric, k, _, _) => {
      @encode.key(out, "exact")
      @encode.bool_value(out, true)
      @encode.key(out, "k")
      @encode.number_value(out, k.to_double())
      @encode.key(out, "metric")
      @encode.string_value(
        out,
        match metric {
          @vector_checking.Cosine => "cosine"
          @vector_checking.Dot => "dot"
          @vector_checking.L2 => "l2"
        },
      )
    }
    VectorPoolParams(groups, reduction, output_id, vector, _, _) => {
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
      if include_pool_vector && vector is Some(name) {
        @encode.key(out, "vector")
        @encode.string_value(out, name)
      }
    }
    VectorRankingParams(ranking) => {
      @encode.key(out, "by")
      @encode.begin_array(out)
      for field in ranking.by {
        @encode.string_value(out, field)
      }
      @encode.end_array(out)
      @encode.key(out, "candidate")
      @encode.string_value(out, ranking.candidate)
      @encode.key(out, "k")
      @encode.number_value(out, ranking.k.to_double())
      if ranking.rank is Some(name) {
        @encode.key(out, "rank")
        @encode.string_value(out, name)
      }
      if ranking.score is Some(name) {
        @encode.key(out, "score")
        @encode.string_value(out, name)
      }
      if ranking.contract is Some(contract) {
        @encode.key(out, "score_contract")
        @encode.begin_object(out)
        @encode.key(out, "domain")
        @encode.string_value(out, contract.domain)
        @encode.key(out, "normalization")
        @encode.string_value(out, contract.normalization)
        @encode.key(out, "range")
        @encode.begin_array(out)
        @encode.number_value(out, contract.minimum)
        @encode.number_value(out, contract.maximum)
        @encode.end_array(out)
        @encode.end_object(out)
      }
      @encode.key(out, "score_policy")
      match ranking.policy {
        RankingMaximum => @encode.string_value(out, "max")
        RankingWeightedSum(left, right) => {
          @encode.begin_object(out)
          @encode.key(out, "weighted_sum")
          @encode.begin_object(out)
          @encode.key(out, "left")
          @encode.number_value(out, left)
          @encode.key(out, "right")
          @encode.number_value(out, right)
          @encode.end_object(out)
          @encode.end_object(out)
        }
        RankingRrf(rank_constant, weights, rank_window) => {
          @encode.begin_object(out)
          @encode.key(out, "rrf")
          @encode.begin_object(out)
          @encode.key(out, "rank_constant")
          @encode.number_value(out, rank_constant)
          @encode.key(out, "rank_window")
          @encode.number_value(out, rank_window)
          @encode.key(out, "weights")
          @encode.begin_array(out)
          for weight in weights {
            @encode.number_value(out, weight)
          }
          @encode.end_array(out)
          @encode.end_object(out)
          @encode.end_object(out)
        }
      }
      if ranking.tie_break is Some(fields) {
        @encode.key(out, "tie_break")
        @encode.begin_array(out)
        for field in fields {
          @encode.string_value(out, field)
        }
        @encode.end_array(out)
      }
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}

///|
fn emit_vector_column(
  out : @encode.Writer,
  name : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "path")
  @encode.begin_array(out)
  @encode.string_value(out, name)
  @encode.end_array(out)
  @encode.key(out, "type")
  @encode.string_value(out, "col")
  @encode.end_object(out)
}

///|
fn emit_vector_function(
  out : @encode.Writer,
  name : String,
  emit_arguments : () -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "args")
  @encode.begin_array(out)
  emit_arguments()
  @encode.end_array(out)
  @encode.key(out, "name")
  @encode.string_value(out, name)
  @encode.key(out, "type")
  @encode.string_value(out, "function")
  @encode.end_object(out)
}

///|
fn emit_vector_string_literal(
  out : @encode.Writer,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "type")
  @encode.string_value(out, "lit")
  @encode.key(out, "value")
  @encode.string_value(out, value)
  @encode.end_object(out)
}

///|
fn emit_pool_identity_component(
  out : @encode.Writer,
  field : String,
) -> Unit raise @encode.EncodeFailure {
  emit_vector_function(out, "to_string", () => {
    emit_vector_function(out, "len", () => {
      emit_vector_function(out, "to_string", () => {
        emit_vector_column(out, field)
      })
    })
  })
  emit_vector_string_literal(out, ":")
  emit_vector_function(out, "to_string", () => emit_vector_column(out, field))
  emit_vector_string_literal(out, "|")
}

///|
fn emit_pool_identity_node(
  prepared : PreparedVector,
  input : String,
  fields : Array[String],
  out : @encode.Writer,
) -> String raise @encode.EncodeFailure {
  let id = vector_generated_role_id(prepared.step, "member_identity")
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, input)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.derive")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "exprs")
  @encode.begin_object(out)
  @encode.key(out, "__actql_vector_record_id")
  emit_vector_function(out, "concat", () => {
    for field in fields {
      emit_pool_identity_component(out, field)
    }
  })
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
  id
}

///|
fn emit_pool_bridge_node(
  prepared : PreparedVector,
  input : String,
  identity : String,
  vector : String,
  out : @encode.Writer,
) -> String raise @encode.EncodeFailure {
  let id = vector_generated_role_id(prepared.step, "members")
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, input)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "BRIDGE.rows.to_vectors")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, identity)
  @encode.key(out, "vector")
  @encode.string_value(out, vector)
  @encode.end_object(out)
  @encode.end_object(out)
  id
}

///|
fn emit_nearest_bridge_node(
  prepared : PreparedVector,
  role : String,
  input : String,
  fields : PreparedVectorBridgeRoles,
  out : @encode.Writer,
) -> String raise @encode.EncodeFailure {
  let id = vector_generated_role_id(prepared.step, role)
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, input)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "BRIDGE.rows.to_vectors")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, fields.identity)
  @encode.key(out, "vector")
  @encode.string_value(out, fields.vector)
  @encode.end_object(out)
  @encode.end_object(out)
  id
}

///|
fn emit_vector_node(
  prepared : PreparedVector,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match prepared.params {
    VectorNearestParams(_, _, candidate, query) => {
      guard prepared.node.inputs.get(0) is Some(candidate_input) &&
        prepared.node.inputs.get(1) is Some(query_input) else {
        raise @encode.InvalidStructure
      }
      let candidate_input = match candidate {
        Some(fields) =>
          emit_nearest_bridge_node(
            prepared, "candidates", candidate_input, fields, out,
          )
        None => candidate_input
      }
      let query_input = match query {
        Some(fields) =>
          emit_nearest_bridge_node(
            prepared, "queries", query_input, fields, out,
          )
        None => query_input
      }
      // AoA orders the query set before the candidate corpus. The checked
      // operation edges retain their authored candidate/query positions.
      emit_vector_operation(
        prepared,
        [query_input, candidate_input],
        false,
        out,
      )
    }
    VectorPoolParams(_, _, _, vector, identities, encoded) => {
      if identities.is_empty() {
        emit_vector_operation(prepared, prepared.node.inputs, true, out)
        return
      }
      guard prepared.node.inputs.get(0) is Some(source) &&
        vector is Some(vector_name) else {
        raise @encode.InvalidStructure
      }
      let member_input = if encoded {
        emit_pool_identity_node(prepared, source, identities, out)
      } else {
        source
      }
      let identity = if encoded {
        "__actql_vector_record_id"
      } else {
        identities[0]
      }
      let vectors = emit_pool_bridge_node(
        prepared, member_input, identity, vector_name, out,
      )
      emit_vector_operation(prepared, [vectors], false, out)
    }
    _ => emit_vector_operation(prepared, prepared.node.inputs, true, out)
  }
}
