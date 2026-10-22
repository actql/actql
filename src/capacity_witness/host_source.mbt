///|
/// Canonical Host-source claim from an admitted Policy field. This constructs
/// integrity and shape only; the existing Host owner still selects the exact
/// field/unit/law application. It issues no data bound or enforcement fact.
pub fn create_host_source(
  ceiling : @policy.Ceiling,
  unit : @arithmetic.BoundUnit,
  law : @law.RegisteredLaw,
  limits : Limits,
) -> Result[WireWitness, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let policy_cid = @policy.cid(@policy.ceiling_policy(ceiling))
  let pending : WireWitness = {
    body: HostSource(ceiling),
    cid: "",
    source: HostPolicy(@policy.ceiling_field(ceiling), policy_cid),
    law,
    unit,
    role: @arithmetic.HostCeiling,
    value: @policy.ceiling_value(ceiling),
    derivation: SourceValue,
    dependencies: [policy_cid],
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_host_source(pending, ceiling, writer, false)
    let cid = "sha256:" + @encode.finish_hash(writer)
    Ok({ ..pending, cid, })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
fn host_source_unit_text(unit : @arithmetic.BoundUnit) -> String {
  match unit {
    Rows => "rows"
    DistinctKeys => "distinct_keys"
    EffectItems => "effect_items"
    Bytes => "bytes"
    ArrayItems => "array_items"
    Nodes => "nodes"
    Edges => "edges"
    Paths => "paths"
    MatchesPerKey => "matches_per_key"
  }
}

///|
fn emit_host_source(
  w : WireWitness,
  ceiling : @policy.Ceiling,
  writer : @encode.Writer,
  include_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  let policy_cid = @policy.cid(@policy.ceiling_policy(ceiling))
  @encode.begin_object(writer)
  @encode.key(writer, "dependencies")
  @encode.begin_array(writer)
  @encode.string_value(writer, policy_cid)
  @encode.end_array(writer)
  @encode.key(writer, "derivation")
  @encode.begin_object(writer)
  @encode.key(writer, "op")
  @encode.string_value(writer, "source")
  @encode.end_object(writer)
  @encode.key(writer, "law_id")
  @encode.string_value(writer, @law.name(w.law))
  @encode.key(writer, "role")
  @encode.string_value(writer, "host_ceiling")
  @encode.key(writer, "source")
  @encode.begin_object(writer)
  @encode.key(writer, "field")
  @encode.string_value(writer, @policy.ceiling_field(ceiling))
  @encode.key(writer, "kind")
  @encode.string_value(writer, "host_policy")
  @encode.key(writer, "policy_cid")
  @encode.string_value(writer, policy_cid)
  @encode.end_object(writer)
  @encode.key(writer, "unit")
  @encode.string_value(writer, host_source_unit_text(w.unit))
  @encode.key(writer, "value")
  @encode.number_value(writer, @policy.ceiling_value(ceiling).to_double())
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-bound-witness/0.1")
  if include_identity {
    @encode.key(writer, "witness_cid")
    @encode.string_value(writer, w.cid)
  }
  @encode.end_object(writer)
}

///|
// An external limit candidate remains fully closed and compared with its
// admitted original. A generated Host source needs no invented parsed cursor.
fn same_witness_body(candidate : @decode.Cursor, witness : WireWitness) -> Bool {
  match witness.body {
    Parsed(cursor) => same_cursor(candidate, cursor)
    HostSource(_) | ProgramSourceValue =>
      try {
        let object = get(
          @decode.closed_object(candidate, [
            "version", "unit", "value", "role", "source", "law_id", "derivation",
            "dependencies", "witness_cid",
          ]),
        )
        let (source, role, _) = read_source(
          get(@decode.required(object, "source")),
        )
        let (derivation, references) = read_derivation(
          get(@decode.required(object, "derivation")),
        )
        let dependencies = identities(
          get(@decode.required(object, "dependencies")),
          true,
        )
        text(object, "version") == "actql-bound-witness/0.1" &&
        identity(object, "witness_cid") == witness.cid &&
        source == witness.source &&
        role == witness.role &&
        text(object, "role") == role_name(witness.role) &&
        text(object, "law_id") == @law.name(witness.law) &&
        read_unit(text(object, "unit")) == witness.unit &&
        number(object, "value") == witness.value &&
        derivation is SourceValue &&
        references.is_empty() &&
        dependencies.length() == 1 &&
        dependencies[0] == witness.dependencies[0]
      } catch {
        _ => false
      }
  }
}
