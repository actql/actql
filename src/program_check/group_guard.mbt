///|
// Emits an owned authored restriction, never evidence of observed item counts.
pub fn unit_group_guard_witness(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> @wire.WireWitness? raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let (source, limit) = owned_group_array_limit(
    program, stage, step, aggregate, budget,
  )
  guard @context.group_array_limit_guard(limit) is Some(value) else {
    return None
  }
  Some(emit_group_guard_witness(source, value, budget))
}

///|
// Private preimage constructor. Its caller obtains the source and bound value
// from the same completed operation closure; callers cannot supply those parts.
fn emit_group_guard_witness(
  source : GroupAggregateSource,
  value : Int64,
  budget : IdentityBudget,
) -> @wire.WireWitness raise UnitBuildFailure {
  emit_aggregate_guard_witness(
    source.operation,
    @relation.aggregate_name(source.call),
    source.scope,
    group_collection(source) + ".aggregates",
    value,
    budget,
  )
}

///|
fn emit_aggregate_guard_witness(
  operation : UnitOperationSource,
  call_name : String,
  scope : String,
  collection : String,
  value : Int64,
  budget : IdentityBudget,
) -> @wire.WireWitness raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  let field = match scope {
    "items" => "max_items"
    "bytes" => "max_bytes"
    _ => raise ForeignOwner
  }
  let encoded_name = publication_metadata(
    w => @encode.string_value(w, call_name) catch { e => raise Encoding(e) },
    remaining,
  )
  identity_charge(remaining, encoded_name.length())
  let name = @utf8.decode(encoded_name) catch { _ => raise ForeignOwner }
  identity_charge(remaining, name.length())
  identity_charge(remaining, 64)
  let path = "$.steps[" +
    operation.source_ordinal.to_string() +
    "]." +
    collection +
    "[" +
    name +
    "]." +
    field
  let definition = operation.unit_definition_cid
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "dependencies")
      @encode.begin_array(w)
      @encode.string_value(w, definition)
      @encode.end_array(w)
      @encode.key(w, "derivation")
      @encode.begin_object(w)
      @encode.key(w, "op")
      @encode.string_value(w, "source")
      @encode.end_object(w)
      @encode.key(w, "law_id")
      @encode.string_value(
        w,
        if scope == "items" {
          "actql.guard.array-aggregate"
        } else {
          "actql.guard.string-aggregate"
        },
      )
      @encode.key(w, "role")
      @encode.string_value(w, "author_guard")
      @encode.key(w, "source")
      @encode.begin_object(w)
      @encode.key(w, "kind")
      @encode.string_value(w, "author_guard")
      @encode.key(w, "program_definition_cid")
      @encode.string_value(w, definition)
      @encode.key(w, "source_path")
      @encode.string_value(w, path)
      @encode.end_object(w)
      @encode.key(w, "unit")
      @encode.string_value(
        w,
        if scope == "items" {
          "array_items"
        } else {
          "bytes"
        },
      )
      @encode.key(w, "value")
      @encode.number_value(w, value.to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-witness/0.1")
      if cid is Some(cid) {
        @encode.key(w, "witness_cid")
        @encode.string_value(w, cid)
      }
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit(hash, None)
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(w => emit(w, Some(cid)), remaining)
  identity_charge(remaining, bytes.length())
  let witness = match
    @wire.admit(bytes, cid, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  witness
}
