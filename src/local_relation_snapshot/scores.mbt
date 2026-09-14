///|
/// Static input assertion. Integrity admission does not authenticate its meaning.
pub struct ScoreDeclaration {
  source : @decode.Cursor
  domain : String
  normalization : String
  minimum : Double
  maximum : Double
  explicit_higher_is_better : Bool
}

///|
fn read_scores(
  root : @decode.ObjectView,
  schema : @schema.Schema,
) -> Array[(String, ScoreDeclaration)]? raise Stop {
  guard @decode.lookup(root, "score_contracts") is Some(at) else { return None }
  guard @decode.object_length(at) is Some(count) else {
    raise Stop(InvalidSnapshot)
  }
  let scores = []
  for i in 0..<count {
    let (field, source) = @decode.field_at(at, i).unwrap()
    guard @schema.lookup(schema, @schema.Unqualified(field))
      is Some({ nullable: false, shape: Number, }) else {
      raise Stop(InvalidSnapshot)
    }
    guard @decode.closed_object(source, [
        "domain", "normalization", "range", "higher_is_better",
      ])
      is Ok(body) else {
      raise Stop(InvalidSnapshot)
    }
    let domain = string(body, "domain")
    let normalization = string(body, "normalization")
    if domain.is_empty() || normalization.is_empty() {
      raise Stop(InvalidSnapshot)
    }
    let explicit = @decode.lookup(body, "higher_is_better") is Some(_)
    if explicit {
      guard @decode.boolean(@decode.lookup(body, "higher_is_better").unwrap())
        is Ok(true) else {
        raise Stop(InvalidSnapshot)
      }
    }
    guard @decode.required(body, "range") is Ok(range) &&
      @decode.array_length(range) == Some(2) &&
      @decode.finite_number(@decode.element_at(range, 0).unwrap())
      is Ok(minimum) &&
      @decode.finite_number(@decode.element_at(range, 1).unwrap())
      is Ok(maximum) &&
      minimum <= maximum else {
      raise Stop(InvalidSnapshot)
    }
    scores.push(
      (
        field,
        {
          source,
          domain,
          normalization,
          minimum,
          maximum,
          explicit_higher_is_better: explicit,
        },
      ),
    )
  }
  Some(scores)
}

///|
fn emit_scores(
  value : Snapshot,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  guard value.scores is Some(scores) else { return }
  @encode.key(out, "score_contracts")
  @encode.begin_object(out)
  for (field, score) in scores {
    @encode.key(out, field)
    @encode.begin_object(out)
    @encode.key(out, "domain")
    @encode.string_value(out, score.domain)
    if score.explicit_higher_is_better {
      @encode.key(out, "higher_is_better")
      @encode.bool_value(out, true)
    }
    @encode.key(out, "normalization")
    @encode.string_value(out, score.normalization)
    @encode.key(out, "range")
    @encode.begin_array(out)
    @encode.number_value(out, score.minimum)
    @encode.number_value(out, score.maximum)
    @encode.end_array(out)
    @encode.end_object(out)
  }
  @encode.end_object(out)
}

///|
pub fn score_count(value : Snapshot) -> Int {
  match value.scores {
    Some(scores) => scores.length()
    None => 0
  }
}

///|
/// Owned admitted map for bounded downstream assertion construction.
pub fn score_source(value : Snapshot) -> @decode.Cursor? {
  value.score_source
}

///|
pub fn score_at(value : Snapshot, index : Int) -> (String, ScoreDeclaration)? {
  match value.scores {
    Some(scores) => scores.get(index)
    None => None
  }
}
