///|
// Geometry only: the fixed-width CID placeholder never escapes as issued
// evidence. Original checked meaning, predicate support and parameter binding
// use the SAME compiler functions as the actual Facts writer. No key, map,
// canonical tree, complete output wire or second compilation is constructed here.
fn measure_client_explanation_body(
  plan : @publication.PublicationContract,
  prepared : PreparedClientProgram,
  b : Int,
  n : Int,
  d : Int,
  complete : Bool,
) -> Result[(Int, Int, Int), ClientExplanationFactsIssue] {
  let identity = prepared_client_identity(prepared)
  let checked = @strategy.graph_program(prepared.graph)
  try {
    let w = @encode.measuring_writer(b, n, d)
    @encode.begin_object(w)
    explanation_text(w, "compiled_plan_cid", interactive_geometry_cid)
    explanation_text(w, "disclosure", "structural")
    explanation_text(w, "logical_map_cid", interactive_geometry_cid)
    explanation_text(w, "parameter_values_cid", identity.parameter_values_cid)
    explanation_text(
      w,
      "program_definition_cid",
      identity.program_definition_cid,
    )
    if complete {
      explanation_text(w, "self_cid", interactive_geometry_cid)
    }
    @encode.key(w, "steps")
    @encode.begin_array(w)
    for stage in 0..<@checked.unit_count(checked) {
      guard @checked.unit_pipeline(checked, stage) is Some(pipeline) else {
        return Err(Meaning(Original(MissingCheckedOccurrence)))
      }
      let count = @pipeline.step_count(pipeline)
      let input_only = count == 0
      for occurrence in 0..<(if input_only { 1 } else { count }) {
        let fact = match
          issue_client_operation_explanation(prepared, plan, stage, occurrence) {
          Ok(value) => value
          Err(issue) => return Err(Meaning(Original(issue)))
        }
        let step = if input_only {
          None
        } else {
          guard @pipeline.step_at(pipeline, occurrence) is Some(step) else {
            return Err(Meaning(Original(MissingCheckedOccurrence)))
          }
          Some(step)
        }
        let input_count = match step {
          None => 1
          Some(value) => @pipeline.input_occurrence_count(value)
        }
        let projected = match fact.meaning {
          Filter(predicate) =>
            match explanation_predicate_supported(predicate, n) {
              Ok(value) => value
              Err(issue) => return Err(Meaning(issue))
            }
          _ => false
        }
        @encode.begin_object(w)
        @encode.key(w, "input_ports")
        @encode.begin_array(w)
        for _ in 0..<input_count {
          @encode.string_value(w, interactive_geometry_cid)
        }
        @encode.end_array(w)
        @encode.key(w, "key")
        interactive_geometry_step_key(w, stage, occurrence, input_only)
        @encode.key(w, "meaning")
        write_client_explanation_meaning(w, fact.meaning, projected)
        @encode.key(w, "operator")
        match step {
          None => @encode.null_value(w)
          Some(value) => {
            guard @decode.object_length(value.source) is Some(fields) else {
              return Err(Meaning(Original(MissingCheckedOccurrence)))
            }
            let mut operator = None
            for index in 0..<fields {
              guard @decode.field_at(value.source, index) is Some((field, _)) else {
                return Err(Meaning(Original(MissingCheckedOccurrence)))
              }
              if field != "from" && field != "as" && field != "meta" {
                operator = Some(field)
              }
            }
            match operator {
              None => @encode.null_value(w)
              Some(name) => @encode.string_value(w, name)
            }
          }
        }
        @encode.key(w, "output_ports")
        @encode.begin_array(w)
        @encode.string_value(w, interactive_geometry_cid)
        @encode.end_array(w)
        explanation_text(w, "step_id", interactive_geometry_cid)
        @encode.end_object(w)
      }
    }
    @encode.end_array(w)
    explanation_text(w, "version", "actql-explanation-facts/0.1")
    @encode.end_object(w)
    Ok(@encode.finish_measurement_usage(w))
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Measure the SAME first compiler projection BEFORE issuing any Plan key/map
/// or Facts value. Its owner must first back measuring writers, original name
/// observations and quotation controls. The returned geometry grants nothing.
/// A normal Saved read must use its retained bytes, never this first issuer.
pub fn measure_client_compiled_explanation_facts(
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  if !client_compiled_run_matches(compiled, prepared) {
    return Err(ForeignOriginal)
  }
  measure_client_pure_compilation_explanation_facts(
    compiled.compilation,
    prepared,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Measure the SAME Request compiler before Run adoption. No policy, clock,
/// definition binding or compiled-Run issuer is needed for structural geometry.
/// As with the Run entry, real Request construction backing must precede this
/// call; equal Plan identities cannot substitute for the compiler's owner.
pub fn measure_client_pure_compilation_explanation_facts(
  compilation : ClientRunCompilation,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  let plan = match
    client_pure_compilation_original_plan(prepared, compilation) {
    Err(ForeignCompilation) => return Err(ForeignOriginal)
    Err(issue) => return Err(OriginalPlan(issue))
    Ok(value) => value
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidReadLimits)
  }
  let body = match
    measure_client_explanation_body(
      plan, prepared, max_bytes, max_nodes, max_depth, false,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let complete = match
    measure_client_explanation_body(
      plan, prepared, max_bytes, max_nodes, max_depth, true,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({ body, complete, })
}
