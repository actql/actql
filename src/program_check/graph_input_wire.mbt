///|
fn emit_graph_input_limit(
  reference : String,
  measure : String,
  host : @host.Witness,
  writer : @encode.Writer,
  cid : String?,
) -> Unit raise UnitBuildFailure {
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "author_guard_binding")
    @encode.string_value(writer, "absent")
    @encode.key(writer, "breach")
    @encode.string_value(writer, "fail")
    @encode.key(writer, "candidates")
    @encode.begin_array(writer)
    @host.emit(host, writer)
    @encode.end_array(writer)
    @encode.key(writer, "effective_max")
    @encode.number_value(
      writer,
      @policy.ceiling_value(@host.ceiling(host)).to_double(),
    )
    @encode.key(writer, "enforcement")
    @encode.string_value(writer, "unit_preflight")
    if cid is Some(cid) {
      @encode.key(writer, "resolved_limit_cid")
      @encode.string_value(writer, cid)
    }
    @encode.key(writer, "subject_ref")
    @encode.string_value(writer, reference + "/" + measure)
    @encode.key(writer, "unit")
    @encode.string_value(writer, measure)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-resolved-limit/0.1")
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}

///|
fn emit_graph_input_witness(
  reference : String,
  measure : String,
  maximum : Int64,
  limit_cid : String,
  writer : @encode.Writer,
  cid : String?,
) -> Unit raise UnitBuildFailure {
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dependencies")
    @encode.begin_array(writer)
    @encode.string_value(writer, limit_cid)
    @encode.end_array(writer)
    @encode.key(writer, "derivation")
    @encode.begin_object(writer)
    @encode.key(writer, "op")
    @encode.string_value(writer, "enforced_ceiling")
    @encode.key(writer, "resolved_limit_cid")
    @encode.string_value(writer, limit_cid)
    @encode.end_object(writer)
    @encode.key(writer, "law_id")
    @encode.string_value(writer, "actql.bound.graph-input-" + measure)
    @encode.key(writer, "role")
    @encode.string_value(writer, "proven_upper_bound")
    @encode.key(writer, "source")
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "program")
    @encode.key(writer, "proof_cid")
    @encode.string_value(writer, limit_cid)
    @encode.key(writer, "semantic_ref")
    @encode.string_value(writer, reference)
    @encode.end_object(writer)
    @encode.key(writer, "unit")
    @encode.string_value(writer, measure)
    @encode.key(writer, "value")
    @encode.number_value(writer, maximum.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-bound-witness/0.1")
    if cid is Some(cid) {
      @encode.key(writer, "witness_cid")
      @encode.string_value(writer, cid)
    }
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}
