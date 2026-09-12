///|
pub(all) enum Operation {
  ToVectors
  NormalizeVectors
  ScoreVectors
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
  b : @checking.Budget,
  c : @decode.Cursor,
  params : Map[String, @contract.ParameterType],
) -> Query raise @checking.Stop {
  if @decode.view(c) is ArrayValue(xs) {
    if xs.is_empty() {
      @checking.fail(c, InvalidQuery)
    }
    @checking.spend(b, c, xs.length())
    let values = []
    for x in xs {
      values.push(@checking.decoded(@decode.finite_number(x)))
    }
    return {
      parameter: None,
      values: Some(values),
      dimensions: Some(xs.length().to_double()),
    }
  }
  let object = @checking.decoded(@decode.closed_object(c, ["$param"]))
  let name = @checking.decoded(
    @decode.text(@checking.decoded(@decode.required(object, "$param"))),
  )
  let ty = match params.get(name) {
    Some(ty) => ty
    None => @checking.fail(c, UnknownParameter(name))
  }
  if ty.contract.nullable {
    @checking.fail(c, IncompatibleParameter(name))
  }
  guard ty.rule is @contract.Items(item, length~) else {
    @checking.fail(c, IncompatibleParameter(name))
  }
  if item.contract.nullable || !(item.contract.shape is @contract.Number) {
    @checking.fail(c, IncompatibleParameter(name))
  }
  if ty.contract.shape is @contract.Array(_, max_items=Some(0L)) {
    @checking.fail(c, IncompatibleParameter(name))
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
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    @checking.scan(b, source)
    let expected = if operation == ToVectors {
      @carrier.RelationKind
    } else {
      @carrier.VectorsKind
    }
    if @carrier.kind(input) != expected {
      @checking.fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let params : Map[String, @contract.ParameterType] = Map([])
    if parameters is Some(ds) {
      let n = @parameter.declaration_count(ds)
      @checking.spend(b, source, n)
      for i in 0..<n {
        let d = @parameter.declaration_at(ds, i).unwrap()
        @checking.charge(b, source, d.name)
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
        let object = @checking.decoded(
          @decode.closed_object(source, ["id", "vector"]),
        )
        let id_source = @checking.decoded(@decode.required(object, "id"))
        let vector_source = @checking.decoded(
          @decode.required(object, "vector"),
        )
        let id = @checking.role_name(id_source)
        let components = @checking.role_name(vector_source)
        let records = @carrier.relation_rows(input).unwrap()
        @checking.spend(b, source, 2)
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
            @checking.fail(at, InvalidRole(e))
          }
        }
        (output, None, None)
      }
      NormalizeVectors => {
        if @decode.boolean(source) != Ok(true) {
          @checking.fail(source, InvalidBody)
        }
        pending.push(NormalizeArithmetic)
        (input, None, None)
      }
      ScoreVectors => {
        let object = @checking.decoded(
          @decode.closed_object(source, ["query", "metric"]),
        )
        let metric_source = @checking.decoded(
          @decode.required(object, "metric"),
        )
        let metric : Metric = match
          @checking.decoded(@decode.text(metric_source)) {
          "cosine" => Cosine
          "dot" => Dot
          "l2" => L2
          _ => @checking.fail(metric_source, InvalidBody)
        }
        let query_source = @checking.decoded(@decode.required(object, "query"))
        let query = read_query(b, query_source, params)
        if query.parameter is Some(name) {
          pending.push(BindQuery(name))
        }
        pending.push(MatchDimensions)
        guard input is @carrier.VectorValue(v) else {
          @checking.fail(source, UnknownOutputFields)
        }
        if query.dimensions is Some(actual) &&
          actual != @carrier.vector_dimensions(v) {
          @checking.fail(
            query_source,
            DimensionMismatch(@carrier.vector_dimensions(v), actual),
          )
        }
        let records = @carrier.vector_records(v)
        match @carrier.lookup(records, Unqualified("score")) {
          Absent => ()
          Present(_) => @checking.fail(source, OutputCollision("score"))
          Unknown => @checking.fail(source, UnknownOutputFields)
        }
        let n = @carrier.field_count(records)
        @checking.spend(b, source, n)
        let fields = []
        for i in 0..<n {
          let f = @carrier.field_at(records, i).unwrap()
          @checking.charge(b, source, @row.reference_name(f.name))
          fields.push((f.name, f.contract))
        }
        @checking.spend(b, source, 1)
        @checking.charge(b, source, "score")
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
          Err(_) => @checking.fail(source, BudgetExceeded)
        }
        let identities = @carrier.vector_identities(v)
        @checking.spend(b, source, identities.length())
        let output = match
          @carrier.vectors(
            records,
            ids=identities.map(f => f.name),
            components=@carrier.vector_components(v).name,
            max_identity_fields=identities.length(),
          ) {
          Ok(c) => c
          Err(_) => @checking.fail(source, InvalidBody)
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
    @checking.Stop(e) => Err(e)
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
/// Literal components without copying; symbolic queries have no component array.
pub fn query_value_count(query : Query) -> Int? {
  query.values.map(v => v.length())
}

///|
pub fn query_value_at(query : Query, index : Int) -> Double? {
  query.values.bind(v => v.get(index))
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
/// O(1), without materializing the obligation array.
pub fn pending_validation_count(value : CheckedVector) -> Int {
  value.pending.length()
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn pending_validation_at(value : CheckedVector, index : Int) -> Obligation? {
  value.pending.get(index)
}

///|
pub fn usage(value : CheckedVector) -> Usage {
  value.usage
}
