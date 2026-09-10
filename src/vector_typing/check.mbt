///|
pub(all) enum Operation {
  ToVectors
  NormalizeVectors
  ScoreVectors
} derive(Eq, Debug)

///|
pub(all) enum Metric {
  Cosine
  Dot
  L2
} derive(Eq, Debug)

///|
pub(all) enum Obligation {
  ValidateVectorValues
  ValidateUniqueIdentities
  ResolveVecaProfile
  ResolveVectorResources
  NormalizeArithmetic
  ScoreArithmetic
  ScoreOrder
  BindQuery(String)
  MatchDimensions
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  WrongCarrier(@carrier.Kind)
  InvalidQuery
  UnknownParameter(String)
  IncompatibleParameter(String)
  DimensionMismatch(Double, Double)
  OutputCollision(String)
  UnknownOutputFields
  InvalidRole(@carrier.Issue)
  MissingNearestRole(String)
  ConflictingNearestRole(String)
  IncompleteNearestInput
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct Query {
  parameter : String?
  values : Array[Double]?
  dimensions : Double?
}

///|
struct CheckedVector {
  source : @decode.Cursor
  operation : Operation
  input : @carrier.Carrier
  output : @carrier.Carrier
  query : Query?
  metric : Metric?
  pending : Array[Obligation]
  usage : Usage
}

///|
fn read_query(
  b : Budget,
  c : @decode.Cursor,
  params : Map[String, @contract.ParameterType],
) -> Query raise Stop {
  if @decode.view(c) is ArrayValue(xs) {
    if xs.is_empty() {
      fail(c, InvalidQuery)
    }
    spend(b, c, xs.length())
    let values = []
    for x in xs {
      values.push(decoded(@decode.finite_number(x)))
    }
    return {
      parameter: None,
      values: Some(values),
      dimensions: Some(xs.length().to_double()),
    }
  }
  let object = decoded(@decode.closed_object(c, ["$param"]))
  let name = decoded(@decode.text(decoded(@decode.required(object, "$param"))))
  let ty = match params.get(name) {
    Some(ty) => ty
    None => fail(c, UnknownParameter(name))
  }
  if ty.contract.nullable {
    fail(c, IncompatibleParameter(name))
  }
  guard ty.rule is @contract.Items(item, length~) else {
    fail(c, IncompatibleParameter(name))
  }
  if item.contract.nullable || !(item.contract.shape is @contract.Number) {
    fail(c, IncompatibleParameter(name))
  }
  if ty.contract.shape is @contract.Array(_, max_items=Some(0L)) {
    fail(c, IncompatibleParameter(name))
  }
  {
    parameter: Some(name),
    values: None,
    dimensions: length.map(n => n.to_double()),
  }
}

///|
pub fn check(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedVector, Issue] {
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
    let expected = if operation == ToVectors {
      @carrier.RelationKind
    } else {
      @carrier.VectorsKind
    }
    if @carrier.kind(input) != expected {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(ds) {
      let n = @parameter.declaration_count(ds)
      spend(b, source, n)
      for i in 0..<n {
        let d = @parameter.declaration_at(ds, i).unwrap()
        charge(b, source, d.name)
        params[d.name] = d.parameter_type
      }
    }
    let pending : Array[Obligation] = [
      ValidateVectorValues,
      ValidateUniqueIdentities,
      ResolveVecaProfile,
      ResolveVectorResources,
    ]
    let (output, query, metric) = match operation {
      ToVectors => {
        let object = decoded(@decode.closed_object(source, ["id", "vector"]))
        let id_source = decoded(@decode.required(object, "id"))
        let vector_source = decoded(@decode.required(object, "vector"))
        let id = role_name(id_source)
        let components = role_name(vector_source)
        let records = @carrier.relation_rows(input).unwrap()
        spend(b, source, 2)
        let output = match
          @carrier.vectors(
            records,
            ids=[id],
            components~,
            max_identity_fields=1,
          ) {
          Ok(value) => value
          Err(e) => {
            let at = match e {
              UnknownRole(name) | InvalidRole(name) | DuplicateRole(name) =>
                if name == components {
                  vector_source
                } else {
                  id_source
                }
              _ => source
            }
            fail(at, InvalidRole(e))
          }
        }
        (output, None, None)
      }
      NormalizeVectors => {
        if @decode.boolean(source) != Ok(true) {
          fail(source, InvalidBody)
        }
        pending.push(NormalizeArithmetic)
        (input, None, None)
      }
      ScoreVectors => {
        let object = decoded(@decode.closed_object(source, ["query", "metric"]))
        let metric_source = decoded(@decode.required(object, "metric"))
        let metric = match decoded(@decode.text(metric_source)) {
          "cosine" => Cosine
          "dot" => Dot
          "l2" => L2
          _ => fail(metric_source, InvalidBody)
        }
        let query_source = decoded(@decode.required(object, "query"))
        let query = read_query(b, query_source, params)
        if query.parameter is Some(name) {
          pending.push(BindQuery(name))
        }
        pending.push(MatchDimensions)
        guard input is @carrier.VectorValue(v) else {
          fail(source, UnknownOutputFields)
        }
        if query.dimensions is Some(actual) &&
          actual != @carrier.vector_dimensions(v) {
          fail(
            query_source,
            DimensionMismatch(@carrier.vector_dimensions(v), actual),
          )
        }
        let records = @carrier.vector_records(v)
        match @carrier.lookup(records, Unqualified("score")) {
          Absent => ()
          Present(_) => fail(source, OutputCollision("score"))
          Unknown => fail(source, UnknownOutputFields)
        }
        let n = @carrier.field_count(records)
        spend(b, source, n)
        let fields = []
        for i in 0..<n {
          let f = @carrier.field_at(records, i).unwrap()
          charge(b, source, @row.reference_name(f.name))
          fields.push((f.name, f.contract))
        }
        spend(b, source, 1)
        charge(b, source, "score")
        fields.push(
          (
            Unqualified("score"),
            Some(@contract.primitive(NumberType, nullable=false)),
          ),
        )
        let records = match
          @carrier.rows(
            fields,
            field_set=@carrier.field_set(records),
            max_fields=fields.length(),
            max_name_bytes=limits.max_text_bytes,
          ) {
          Ok(rows) => rows
          Err(_) => fail(source, BudgetExceeded)
        }
        let identities = @carrier.vector_identities(v)
        spend(b, source, identities.length())
        let output = match
          @carrier.vectors(
            records,
            ids=identities.map(f => f.name),
            components=@carrier.vector_components(v).name,
            max_identity_fields=identities.length(),
          ) {
          Ok(c) => c
          Err(_) => fail(source, InvalidBody)
        }
        pending.push(ScoreArithmetic)
        pending.push(ScoreOrder)
        (output, Some(query), Some(metric))
      }
    }
    Ok({
      source,
      operation,
      input,
      output,
      query,
      metric,
      pending,
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
pub fn source(value : CheckedVector) -> @decode.Cursor {
  value.source
}

///|
pub fn operation(value : CheckedVector) -> Operation {
  value.operation
}

///|
pub fn input(value : CheckedVector) -> @carrier.Carrier {
  value.input
}

///|
pub fn output(value : CheckedVector) -> @carrier.Carrier {
  value.output
}

///|
pub fn query(value : CheckedVector) -> Query? {
  value.query
}

///|
pub fn metric(value : CheckedVector) -> Metric? {
  value.metric
}

///|
pub fn query_parameter(query : Query) -> String? {
  query.parameter
}

///|
pub fn query_values(query : Query) -> Array[Double]? {
  query.values.map(v => v.copy())
}

///|
pub fn query_dimensions(query : Query) -> Double? {
  query.dimensions
}

///|
pub fn pending_validations(value : CheckedVector) -> Array[Obligation] {
  value.pending.copy()
}

///|
pub fn usage(value : CheckedVector) -> Usage {
  value.usage
}
