///|
pub struct NearestRoles {
  identity : @row.FieldName?
  vector : @row.FieldName?
}

///|
struct NearestOptions {
  source : @decode.Cursor
  queries : String
  candidate : NearestRoles
  query : NearestRoles
  metric : @checking.Metric
  k : Int64
  usage : @checking.Usage
}

///|
fn nearest_roles(
  object : @decode.ObjectView,
  identity : String,
  vector : String,
) -> NearestRoles raise @checking.Stop {
  let identity = match @decode.lookup(object, identity) {
    Some(at) => Some(@checking.role_name(at))
    None => None
  }
  let vector = match @decode.lookup(object, vector) {
    Some(at) => Some(@checking.role_name(at))
    None => None
  }
  { identity, vector, }
}

///|
/// Admits authored options without resolving input roles or asserting ranking evidence.
pub fn read_nearest_options(
  source : @decode.Cursor,
  limits : @checking.Limits,
) -> Result[NearestOptions, @checking.Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    @checking.scan(b, source)
    let root = @checking.decoded(
      @decode.closed_object(source, [
        "queries", "candidate_id", "candidate_vector", "query_id", "query_vector",
        "metric", "k",
      ]),
    )
    let at = @checking.decoded(@decode.required(root, "queries"))
    let queries = @checking.decoded(@decode.text(at))
    if queries.is_empty() {
      @checking.fail(at, InvalidBody)
    }
    let at = @checking.decoded(@decode.required(root, "metric"))
    let metric : @checking.Metric = match @checking.decoded(@decode.text(at)) {
      "cosine" => Cosine
      "dot" => Dot
      "l2" => L2
      _ => @checking.fail(at, InvalidBody)
    }
    let at = @checking.decoded(@decode.required(root, "k"))
    let k = @checking.decoded(@decode.safe_integer(at))
    if k <= 0L {
      @checking.fail(at, InvalidBody)
    }
    let candidate = nearest_roles(root, "candidate_id", "candidate_vector")
    let query = nearest_roles(root, "query_id", "query_vector")
    Ok({
      source,
      queries,
      candidate,
      query,
      metric,
      k,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn nearest_source(c : NearestOptions) -> @decode.Cursor {
  c.source
}

///|
pub fn nearest_query_name(c : NearestOptions) -> String {
  c.queries
}

///|
pub fn nearest_candidate_roles(c : NearestOptions) -> NearestRoles {
  c.candidate
}

///|
pub fn nearest_query_roles(c : NearestOptions) -> NearestRoles {
  c.query
}

///|
pub fn nearest_metric(c : NearestOptions) -> @checking.Metric {
  c.metric
}

///|
pub fn nearest_k(c : NearestOptions) -> Int64 {
  c.k
}

///|
pub fn nearest_options_usage(c : NearestOptions) -> @checking.Usage {
  c.usage
}

///|
pub(all) enum NearestSide {
  Candidates
  Queries
} derive(Eq, Debug)

///|
struct NearestInput {
  supplied : NearestSource
  vectors : @carrier.Vectors?
  completed_vector : @row.FieldName?
  completed_identity : KeyedRelation?
  usage : @checking.Usage
}

///|
pub(all) enum NearestSource {
  CarrierSource(@carrier.Carrier)
  KeySource(KeySet)
}

///|
/// Resolves typed roles only. It does not prove runtime identity uniqueness.
pub fn check_nearest_input(
  options : NearestOptions,
  side : NearestSide,
  input : @carrier.Carrier,
  limits : @checking.Limits,
) -> Result[NearestInput, @checking.Issue] {
  check_nearest_source(options, side, CarrierSource(input), limits)
}

///|
pub fn check_nearest_source(
  options : NearestOptions,
  side : NearestSide,
  supplied : NearestSource,
  limits : @checking.Limits,
) -> Result[NearestInput, @checking.Issue] {
  try {
    let source = options.source
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    let (roles, id_key, vector_key) = match side {
      Candidates => (options.candidate, "candidate_id", "candidate_vector")
      Queries => (options.query, "query_id", "query_vector")
    }
    let root = @checking.decoded(@decode.open_object(source))
    let id_at = @decode.lookup(root, id_key).unwrap_or(source)
    let vector_at = @decode.lookup(root, vector_key).unwrap_or(source)
    let mut completed_vector = None
    let mut completed_identity = None
    let (input, keys) = match supplied {
      CarrierSource(c) => (c, None)
      KeySource(k) => (@carrier.relation(key_set_records(k)), Some(k))
    }
    let vectors = match input {
      @carrier.VectorValue(v) => {
        // Existing carrier roles are authoritative: optional spellings can only
        // restate the same roles, not silently replace the semantic identity.
        if roles.identity is Some(id) {
          @checking.spend(b, id_at, 1)
          if @carrier.vector_identity_count(v) != 1 ||
            @carrier.vector_identity_at(v, 0).unwrap().name != id {
            @checking.fail(id_at, ConflictingNearestRole(id_key))
          }
        }
        if roles.vector is Some(vector) {
          @checking.spend(b, vector_at, 1)
          if @carrier.vector_components(v).name != vector {
            @checking.fail(vector_at, ConflictingNearestRole(vector_key))
          }
        }
        Some(v)
      }
      @carrier.Relation(rows) => {
        let id = match roles.identity {
          Some(id) => id
          None => {
            guard keys is Some(keys) else {
              @checking.fail(id_at, MissingNearestRole(id_key))
            }
            let selected = match
              select_sole_string_key(id_at, keys, {
                max_work: b.work,
                max_name_bytes: b.text,
              }) {
              Ok(v) => v
              Err(_) => @checking.fail(id_at, BudgetExceeded)
            }
            b.work -= selected.work
            b.text -= selected.name_bytes
            guard selected.key is Some(key) else {
              @checking.fail(id_at, MissingNearestRole(id_key))
            }
            completed_identity = Some(key)
            key_field_at(key, 0).unwrap().name
          }
        }
        let vector = match roles.vector {
          Some(vector) => vector
          None => {
            // A known vector in an open field set is not proof that it is sole.
            if @carrier.field_set(rows) != Closed {
              @checking.fail(vector_at, MissingNearestRole(vector_key))
            }
            @checking.spend(b, vector_at, @carrier.field_count(rows))
            let mut found : @row.FieldName? = None
            for i in 0..<@carrier.field_count(rows) {
              let field = @carrier.field_at(rows, i).unwrap()
              if field.contract is Some(c) && c.shape is @contract.Vector(_) {
                if found is Some(_) {
                  @checking.fail(vector_at, MissingNearestRole(vector_key))
                }
                found = Some(field.name)
              }
            }
            let vector = match found {
              Some(n) => n
              None => @checking.fail(vector_at, MissingNearestRole(vector_key))
            }
            completed_vector = Some(vector)
            vector
          }
        }
        @checking.spend(b, source, 2)
        let out = match
          @carrier.vectors(
            rows,
            ids=[id],
            components=vector,
            max_identity_fields=1,
          ) {
          Ok(c) => c
          Err(e) => {
            let at = match e {
              UnknownRole(n) | InvalidRole(n) | DuplicateRole(n) =>
                if n == vector {
                  vector_at
                } else {
                  id_at
                }
              _ => source
            }
            @checking.fail(at, InvalidRole(e))
          }
        }
        guard out is @carrier.VectorValue(v) else {
          @checking.fail(source, IncompleteNearestInput)
        }
        Some(v)
      }
      @carrier.Opaque(VectorsKind) => None
      _ => @checking.fail(source, WrongCarrier(@carrier.kind(input)))
    }
    Ok({
      supplied,
      vectors,
      completed_vector,
      completed_identity,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
/// Returns the original immutable input, before role completion. Retaining a
/// supplied key collection does not certify its rows or select an unused key.
pub fn nearest_input_source(c : NearestInput) -> NearestSource {
  c.supplied
}

///|
pub fn nearest_input_vectors(c : NearestInput) -> @carrier.Vectors? {
  c.vectors
}

///|
pub fn nearest_completed_vector(c : NearestInput) -> @row.FieldName? {
  c.completed_vector
}

///|
pub fn nearest_completed_identity(c : NearestInput) -> KeyedRelation? {
  c.completed_identity
}

///|
pub fn nearest_input_usage(c : NearestInput) -> @checking.Usage {
  c.usage
}

///|
pub(all) enum NearestObligation {
  ValidateNearestRoleBindings(NearestSide)
  MatchNearestDimensions
  AdmitQuantizedVectorComponents
  ValidateBothUniqueIdentities
  EvaluateExactNearestScores
  RestoreSemanticIdentityValues
  OrderQueriesByIdentity
  OrderCandidatesByDescendingScoreThenIdentity
  AssignContiguousOneBasedRanks
  JournalVectorFieldCompletion(NearestSide, @row.FieldName)
  JournalIdentityFieldCompletion(NearestSide, @row.FieldName)
  ValidateNearestKey(NearestSide, KeyObligation)
  ResolveNearestResources
  ResolveNearestProfile
  PreserveSimilarityAuthorityBoundary
} derive(Eq, Debug)

///|
struct NearestPair {
  options : NearestOptions
  candidates : NearestInput
  queries : NearestInput
  usage : @checking.Usage
}

///|
/// Admits both known input roles under one budget; does not execute KNN.
pub fn check_nearest_pair(
  source : @decode.Cursor,
  candidates : @carrier.Carrier,
  queries : @carrier.Carrier,
  limits : @checking.Limits,
) -> Result[NearestPair, @checking.Issue] {
  check_nearest_pair_sources(
    source,
    CarrierSource(candidates),
    CarrierSource(queries),
    limits,
  )
}

///|
pub fn check_nearest_pair_sources(
  source : @decode.Cursor,
  candidates : NearestSource,
  queries : NearestSource,
  limits : @checking.Limits,
) -> Result[NearestPair, @checking.Issue] {
  try {
    let options = match read_nearest_options(source, limits) {
      Ok(c) => c
      Err(e) => raise @checking.Stop(e)
    }
    let u = options.usage
    let remaining = {
      ..limits,
      max_work: limits.max_work - u.work,
      max_nodes: limits.max_nodes - u.nodes,
      max_text_bytes: limits.max_text_bytes - u.text_bytes,
    }
    let candidates = match
      check_nearest_source(options, Candidates, candidates, remaining) {
      Ok(c) => c
      Err(e) => raise @checking.Stop(e)
    }
    let c = candidates.usage
    let remaining = {
      ..remaining,
      max_work: remaining.max_work - c.work,
      max_nodes: remaining.max_nodes - c.nodes,
      max_text_bytes: remaining.max_text_bytes - c.text_bytes,
    }
    let queries = match
      check_nearest_source(options, Queries, queries, remaining) {
      Ok(c) => c
      Err(e) => raise @checking.Stop(e)
    }
    let q = queries.usage
    if candidates.vectors is Some(a) && queries.vectors is Some(z) {
      let a = @carrier.vector_dimensions(a)
      let z = @carrier.vector_dimensions(z)
      if a != z {
        let root = @checking.decoded(@decode.open_object(source))
        let at = @decode.lookup(root, "query_vector").unwrap_or(
          @checking.decoded(@decode.required(root, "queries")),
        )
        @checking.fail(at, DimensionMismatch(a, z))
      }
    }
    Ok({
      options,
      candidates,
      queries,
      usage: {
        work: u.work + c.work + q.work,
        nodes: u.nodes + c.nodes + q.nodes,
        text_bytes: u.text_bytes + c.text_bytes + q.text_bytes,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn nearest_pair_options(c : NearestPair) -> NearestOptions {
  c.options
}

///|
pub fn nearest_pair_input(c : NearestPair, side : NearestSide) -> NearestInput {
  match side {
    Candidates => c.candidates
    Queries => c.queries
  }
}

///|
pub fn nearest_pair_usage(c : NearestPair) -> @checking.Usage {
  c.usage
}

///|
pub fn nearest_pair_pending(c : NearestPair) -> Array[NearestObligation] {
  let pending = [
    AdmitQuantizedVectorComponents,
    ValidateBothUniqueIdentities,
    EvaluateExactNearestScores,
    RestoreSemanticIdentityValues,
    OrderQueriesByIdentity,
    OrderCandidatesByDescendingScoreThenIdentity,
    AssignContiguousOneBasedRanks,
    ResolveNearestResources,
    ResolveNearestProfile,
    PreserveSimilarityAuthorityBoundary,
  ]
  if c.candidates.vectors is None {
    pending.push(ValidateNearestRoleBindings(Candidates))
  }
  if c.queries.vectors is None {
    pending.push(ValidateNearestRoleBindings(Queries))
  }
  if c.candidates.vectors is None || c.queries.vectors is None {
    pending.push(MatchNearestDimensions)
  }
  if c.candidates.completed_vector is Some(n) {
    pending.push(JournalVectorFieldCompletion(Candidates, n))
  }
  if c.queries.completed_vector is Some(n) {
    pending.push(JournalVectorFieldCompletion(Queries, n))
  }
  for (side, input) in [(Candidates, c.candidates), (Queries, c.queries)] {
    if input.completed_identity is Some(key) {
      pending.push(
        JournalIdentityFieldCompletion(side, key_field_at(key, 0).unwrap().name),
      )
      for obligation in key_pending(key) {
        pending.push(ValidateNearestKey(side, obligation))
      }
    }
  }
  pending
}

///|
struct CheckedNearest {
  pair : NearestPair
  output : @carrier.Carrier
  usage : @checking.Usage
}

///|
fn nearest_identity_contract(
  b : @checking.Budget,
  source : @decode.Cursor,
  input : NearestInput,
) -> @contract.Contract? raise @checking.Stop {
  guard input.vectors is Some(vectors) else { return None }
  let n = @carrier.vector_identity_count(vectors)
  @checking.spend(b, source, n)
  if n == 1 {
    return @carrier.vector_identity_at(vectors, 0).unwrap().contract
  }
  if b.nodes <= 0 || b.limits.max_depth < 1 {
    @checking.fail(source, BudgetExceeded)
  }
  b.nodes -= 1
  let fields : Array[(String, @contract.Contract)] = []
  for i in 0..<n {
    let name = i.to_string()
    @checking.charge(b, source, name)
    fields.push(
      (name, @carrier.vector_identity_at(vectors, i).unwrap().contract.unwrap()),
    )
  }
  match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=n,
      max_name_bytes=b.limits.max_text_bytes,
    ) {
    Ok(c) => Some(c)
    Err(_) => @checking.fail(source, BudgetExceeded)
  }
}

///|
pub fn check_nearest(
  source : @decode.Cursor,
  candidates : @carrier.Carrier,
  queries : @carrier.Carrier,
  limits : @checking.Limits,
) -> Result[CheckedNearest, @checking.Issue] {
  check_nearest_sources(
    source,
    CarrierSource(candidates),
    CarrierSource(queries),
    limits,
  )
}

///|
pub fn check_nearest_sources(
  source : @decode.Cursor,
  candidates : NearestSource,
  queries : NearestSource,
  limits : @checking.Limits,
) -> Result[CheckedNearest, @checking.Issue] {
  try {
    let pair = match
      check_nearest_pair_sources(source, candidates, queries, limits) {
      Ok(p) => p
      Err(e) => raise @checking.Stop(e)
    }
    let u = pair.usage
    let b : @checking.Budget = {
      limits,
      work: limits.max_work - u.work,
      nodes: limits.max_nodes - u.nodes,
      text: limits.max_text_bytes - u.text_bytes,
    }
    let query = nearest_identity_contract(b, source, pair.queries)
    let candidate = nearest_identity_contract(b, source, pair.candidates)
    @checking.spend(b, source, 4)
    if b.nodes < 2 {
      @checking.fail(source, BudgetExceeded)
    }
    b.nodes -= 2
    let number = @contract.primitive(NumberType, nullable=false)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    for
      (name, c) in [
        ("query_id", query),
        ("candidate_id", candidate),
        ("score", Some(number)),
        ("rank", Some(number)),
      ] {
      @checking.charge(b, source, name)
      fields.push((Unqualified(name), c))
    }
    let output = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=4,
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => @carrier.relation(r)
      Err(_) => @checking.fail(source, BudgetExceeded)
    }
    Ok({
      pair,
      output,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn nearest_output(c : CheckedNearest) -> @carrier.Carrier {
  c.output
}

///|
pub fn nearest_pair(c : CheckedNearest) -> NearestPair {
  c.pair
}

///|
pub fn nearest_usage(c : CheckedNearest) -> @checking.Usage {
  c.usage
}

///|
pub fn nearest_pending(c : CheckedNearest) -> Array[NearestObligation] {
  nearest_pair_pending(c.pair)
}
