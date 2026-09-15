///|
fn derived_unit_name(unit : @arithmetic.BoundUnit) -> String {
  match unit {
    Rows => "rows"
    Nodes => "nodes"
    Edges => "edges"
    // Construction rejects units not produced by an operation rule.
    DistinctKeys => "distinct_keys"
    EffectItems => "effect_items"
    Bytes => "bytes"
    ArrayItems => "array_items"
    Paths => "paths"
    MatchesPerKey => "matches_per_key"
  }
}

///|
fn emit_derived_proof(
  subject : String,
  law : String,
  unit : @arithmetic.BoundUnit,
  count : Int64,
  inputs : Array[String],
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "inputs")
  @encode.begin_array(out)
  for id in inputs {
    @encode.string_value(out, id)
  }
  @encode.end_array(out)
  @encode.key(out, "law_id")
  @encode.string_value(out, law)
  @encode.key(out, "semantic_ref")
  @encode.string_value(out, subject)
  @encode.key(out, "unit")
  @encode.string_value(out, derived_unit_name(unit))
  @encode.key(out, "value")
  @encode.number_value(out, count.to_double())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-bound-proof/0.1")
  @encode.end_object(out)
}

///|
fn emit_derived_rule(
  rule : Rule,
  ids : Array[String],
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match rule {
    Preserve => {
      @encode.key(out, "input")
      @encode.string_value(out, ids[0])
      @encode.key(out, "op")
      @encode.string_value(out, "preserve")
    }
    Sum => {
      @encode.key(out, "left")
      @encode.string_value(out, ids[0])
      @encode.key(out, "op")
      @encode.string_value(out, "add")
      @encode.key(out, "right")
      @encode.string_value(out, ids[1])
    }
    Multiply(factor) => {
      @encode.key(out, "factor")
      @encode.number_value(out, factor.to_double())
      @encode.key(out, "input")
      @encode.string_value(out, ids[0])
      @encode.key(out, "op")
      @encode.string_value(out, "multiply")
    }
    Clamp(maximum) => {
      if ids.get(0) is Some(id) {
        @encode.key(out, "input")
        @encode.string_value(out, id)
      }
      @encode.key(out, "maximum")
      @encode.number_value(out, maximum.to_double())
      @encode.key(out, "op")
      @encode.string_value(out, "clamp")
    }
    Ranking(_, Some(maximum)) if ids.is_empty() => {
      @encode.key(out, "maximum")
      @encode.number_value(out, maximum.to_double())
      @encode.key(out, "op")
      @encode.string_value(out, "clamp")
    }
    One
    | Constant(_)
    | GraphQuery(_)
    | GraphMeasure(_, _, _, _)
    | GraphCombine(_, _)
    | Join(_)
    | Ranking(_, _) => {
      @encode.key(out, "op")
      @encode.string_value(out, "source")
    }
    QueryTopK(factor) =>
      if ids.length() == 1 {
        @encode.key(out, "factor")
        @encode.number_value(out, factor.to_double())
        @encode.key(out, "input")
        @encode.string_value(out, ids[0])
        @encode.key(out, "op")
        @encode.string_value(out, "multiply")
      } else {
        @encode.key(out, "op")
        @encode.string_value(out, "source")
      }
  }
  @encode.end_object(out)
}

///|
fn emit_derived_witness(
  subject : String,
  law : String,
  unit : @arithmetic.BoundUnit,
  count : Int64,
  rule : Rule,
  inputs : Array[String],
  proof : String,
  dependencies : Array[String],
  cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "dependencies")
  @encode.begin_array(out)
  for id in dependencies {
    @encode.string_value(out, id)
  }
  @encode.end_array(out)
  @encode.key(out, "derivation")
  emit_derived_rule(rule, inputs, out)
  @encode.key(out, "law_id")
  @encode.string_value(out, law)
  @encode.key(out, "role")
  @encode.string_value(out, "proven_upper_bound")
  @encode.key(out, "source")
  @encode.begin_object(out)
  @encode.key(out, "kind")
  @encode.string_value(out, "program")
  @encode.key(out, "proof_cid")
  @encode.string_value(out, proof)
  @encode.key(out, "semantic_ref")
  @encode.string_value(out, subject)
  @encode.end_object(out)
  @encode.key(out, "unit")
  @encode.string_value(out, derived_unit_name(unit))
  @encode.key(out, "value")
  @encode.number_value(out, count.to_double())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-bound-witness/0.1")
  if cid is Some(id) {
    @encode.key(out, "witness_cid")
    @encode.string_value(out, id)
  }
  @encode.end_object(out)
}
