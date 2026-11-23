///|
/// Borrowed compiler-original metadata, not a Run, authority or new identity.
/// The caller must admit the existing static-plan construction before capture,
/// including its wire/tree overlap, and retain this read under its own scope.
pub struct ClientStructuralExplanationOriginal {
  compiled : ClientCompiledRun
  prepared : PreparedClientProgram
  map : @canonical.CanonicalValue
}

///|
pub(all) enum ClientExplanationFactsIssue {
  OriginalPlan(ClientCompiledRunPlanIssue)
  ForeignOriginal
  InvalidReadLimits
  Meaning(ClientExplanationProjectionIssue)
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Eq, Debug)

///|
/// Exact output extents only. Measurement and original/emit/parse/hash overlap
/// still require real backing from the caller's existing read scope.
pub(all) struct ClientExplanationFactsConstruction {
  body : (Int, Int, Int)
  complete : (Int, Int, Int)
} derive(Eq, Debug)

///|
/// Capture once while the exact compiler owner is retained. Normal/old Runs
/// without retained facts must not call this as historical read repair.
pub fn capture_client_structural_explanation_original(
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientStructuralExplanationOriginal, ClientExplanationFactsIssue] {
  capture_client_structural_explanation_plan_original(
    compiled, prepared, max_bytes, max_nodes, max_depth,
  ).map(value => value.0)
}

///|
/// The first admission can retain BOTH original projections from one compiler
/// pass. Its existing owner must fund the complete static view and hold it
/// beside the Facts construction until that same durable admission ACK.
/// The returned String is the unchanged old Plan view, not a new wire family.
pub fn capture_client_structural_explanation_plan_original(
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientStructuralExplanationOriginal, String),
  ClientExplanationFactsIssue,
] {
  let (wire, view) = match
    capture_client_compiled_static_plan_original(
      compiled, prepared, max_bytes, max_nodes, max_depth, false,
    ) {
    Ok(value) => value
    Err(issue) => return Err(OriginalPlan(issue))
  }
  guard @canonical.object_field(view, "logical_map") is Some(map) else {
    return Err(Encoding(@encode.InvalidStructure))
  }
  Ok(({ compiled, prepared, map, }, wire))
}

///|
fn explanation_original_matches(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
) -> Bool {
  physical_equal(original.compiled, compiled) &&
  physical_equal(original.prepared, prepared) &&
  client_compiled_run_matches(compiled, prepared)
}

///|
/// Borrow the exact compiler-issued map identity beside its still-held Plan.
/// A sealed replacement with different capabilities, ports or keys refuses.
pub fn client_structural_explanation_map_matches(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  map : @publication.RunEvidenceValue,
) -> Bool {
  explanation_original_matches(original, compiled, prepared) &&
  @publication.run_evidence_value_name(map) == "logical_map" &&
  @canonical.object_field(original.map, "self_cid")
  is Some(@canonical.String(identity)) &&
  identity == @publication.run_evidence_value_identity(map)
}

///|
fn explanation_original_text(
  value : @canonical.CanonicalValue,
  field : String,
) -> String raise @encode.EncodeFailure {
  guard @canonical.object_field(value, field) is Some(@canonical.String(text)) else {
    raise @encode.InvalidStructure
  }
  text
}

///|
fn explanation_original_ordinal(
  value : @canonical.CanonicalValue,
  field : String,
) -> Int raise @encode.EncodeFailure {
  guard @canonical.object_field(value, field) is Some(@canonical.Number(number)) &&
    @scalar.read_safe_integer(number) is Some(integer) &&
    integer >= 0L &&
    integer <= 2147483647L else {
    raise @encode.InvalidStructure
  }
  integer.to_int()
}

///|
fn explanation_original_field(
  value : @canonical.CanonicalValue,
  field : String,
) -> @canonical.CanonicalValue raise @encode.EncodeFailure {
  guard @canonical.object_field(value, field) is Some(field) else {
    raise @encode.InvalidStructure
  }
  field
}

///|
fn explanation_original_ports(
  w : @encode.Writer,
  step : @canonical.CanonicalValue,
  role : String,
) -> Unit raise @encode.EncodeFailure {
  guard @canonical.object_field(step, "ports") is Some(@canonical.Array(ports)) else {
    raise @encode.InvalidStructure
  }
  @encode.begin_array(w)
  for i in 0..<@canonical.array_count(ports) {
    let port = @canonical.array_at(ports, i).unwrap()
    if explanation_original_text(port, "role") == role {
      @encode.string_value(w, explanation_original_text(port, "port_id"))
    }
  }
  @encode.end_array(w)
}

///|
fn write_client_explanation_facts(
  w : @encode.Writer,
  prepared : PreparedClientProgram,
  plan : @publication.PublicationContract,
  map : @canonical.CanonicalValue,
  max_nodes : Int,
  complete : Bool,
) -> Result[Unit, ClientExplanationFactsIssue] {
  let identity = prepared_client_identity(prepared)
  try {
    @encode.begin_object(w)
    explanation_text(
      w,
      "compiled_plan_cid",
      explanation_original_text(map, "compiled_plan_cid"),
    )
    explanation_text(w, "disclosure", "structural")
    explanation_text(
      w,
      "logical_map_cid",
      explanation_original_text(map, "self_cid"),
    )
    explanation_text(w, "parameter_values_cid", identity.parameter_values_cid)
    explanation_text(
      w,
      "program_definition_cid",
      identity.program_definition_cid,
    )
    if complete {
      // Sizing only; this placeholder is never returned as admitted facts.
      explanation_text(w, "self_cid", interactive_geometry_cid)
    }
    @encode.key(w, "steps")
    @encode.begin_array(w)
    guard @canonical.object_field(map, "steps") is Some(@canonical.Array(steps)) else {
      raise @encode.InvalidStructure
    }
    for i in 0..<@canonical.array_count(steps) {
      let step = @canonical.array_at(steps, i).unwrap()
      let key = explanation_original_field(step, "key")
      let stage = explanation_original_ordinal(key, "stage_ordinal")
      let occurrence = explanation_original_field(key, "occurrence")
      let index = explanation_original_ordinal(
        occurrence,
        if explanation_original_text(occurrence, "kind") == "input_output" {
          "input_port_ordinal"
        } else {
          "operation_ordinal"
        },
      )
      let fact = match
        issue_client_operation_explanation(prepared, plan, stage, index) {
        Ok(fact) => fact
        Err(issue) => return Err(Meaning(Original(issue)))
      }
      let meaning = fact.meaning
      let projected = match meaning {
        Filter(predicate) =>
          match explanation_predicate_supported(predicate, max_nodes) {
            Ok(value) => value
            Err(issue) => return Err(Meaning(issue))
          }
        _ => false
      }
      @encode.begin_object(w)
      @encode.key(w, "input_ports")
      explanation_original_ports(w, step, "input")
      @encode.key(w, "key")
      @canonical.emit_value(key, w)
      @encode.key(w, "meaning")
      write_client_explanation_meaning(w, meaning, projected)
      @encode.key(w, "operator")
      @canonical.emit_value(explanation_original_field(step, "operator"), w)
      @encode.key(w, "output_ports")
      explanation_original_ports(w, step, "output")
      explanation_text(w, "step_id", explanation_original_text(step, "step_id"))
      @encode.end_object(w)
    }
    @encode.end_array(w)
    explanation_text(w, "version", "actql-explanation-facts/0.1")
    @encode.end_object(w)
    Ok(())
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// No new key issuance, Source parsing, compilation or execution. Only original
/// key/port identities and structural checked meaning enter this new envelope.
pub fn measure_client_structural_explanation_facts(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  if !explanation_original_matches(original, compiled, prepared) {
    return Err(ForeignOriginal)
  }
  measure_client_explanation_facts_from_map(
    prepared,
    original.compiled.plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn measure_client_explanation_facts_from_map(
  prepared : PreparedClientProgram,
  plan : @publication.PublicationContract,
  map : @canonical.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientExplanationFactsConstruction, ClientExplanationFactsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidReadLimits)
  }
  try {
    let body = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    match
      write_client_explanation_facts(
        body, prepared, plan, map, max_nodes, false,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let body_geometry = @encode.finish_measurement_usage(body)
    let complete = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    match
      write_client_explanation_facts(
        complete, prepared, plan, map, max_nodes, true,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let complete_geometry = @encode.finish_measurement_usage(complete)
    Ok({ body: body_geometry, complete: complete_geometry, })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Seal once for retention beside the original Run. Disclosure still requires
/// the existing current Run/Plan read and egress admission/recheck; equality or
/// a self CID cannot grant access. Saved reads use retained original bytes.
pub fn seal_client_structural_explanation_facts(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientExplanationFactsIssue] {
  if !explanation_original_matches(original, compiled, prepared) {
    return Err(ForeignOriginal)
  }
  seal_client_explanation_facts_from_map(
    prepared,
    original.compiled.plan,
    original.map,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn seal_client_explanation_facts_from_map(
  prepared : PreparedClientProgram,
  plan : @publication.PublicationContract,
  map : @canonical.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientExplanationFactsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidReadLimits)
  }
  let body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    match
      write_client_explanation_facts(w, prepared, plan, map, max_nodes, false) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.finish(w)
  } catch {
    issue => return Err(Encoding(issue))
  }
  @publication.seal_run_evidence_value(
    "explanation_facts", body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}
