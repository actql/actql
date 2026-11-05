///|
/// Project only the execution contract retained by the original compilation.
/// The unique checked occurrence owns its coordinates; no saved selector,
/// current installation or caller-supplied replacement is introduced here.
fn client_effect_original_infer_input(
  compilation : ClientEffectCompilation,
) -> Result[(String, String)?, ClientEffectRunMaterialsIssue] {
  guard compilation.compiled.infer is Some(component) else { return Ok(None) }
  guard client_effect_compilation_infer_original(compilation) is Some(_) else {
    return Err(Compilation(ForeignInferOwner))
  }
  try {
    let writer = @encode.writer(65536, 4096, 64)
    @syntax.emit_admitted_source_value(
      @environment.model_execution_source(component.execution),
      writer,
    )
    Ok(
      Some(
        (
          @environment.model_execution_cid(component.execution),
          @encode.finish(writer),
        ),
      ),
    )
  } catch {
    _ => Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
}

///|
/// Pairing is checked before reconstruction. A half-present or non-string
/// execution original is malformed, including on a non-Model Program.
fn read_client_effect_original_infer_input(
  cid : @decode.Cursor?,
  wire : @decode.Cursor?,
) -> Result[(String, String)?, ClientValuesRunMaterialsIssue] {
  match (cid, wire) {
    (None, None) => Ok(None)
    (Some(cid), Some(wire)) =>
      match (@decode.text(cid), @decode.text(wire)) {
        (Ok(cid), Ok(wire)) => Ok(Some((cid, wire)))
        _ => Err(MaterialsMalformed)
      }
    _ => Err(MaterialsMalformed)
  }
}

///|
/// Reconstruct the existing component on this exact restored checked owner.
/// The contract reader rebinds the retained body to that owner's ModelTask;
/// the ordinary composed issuer preserves serialized Content dependencies.
/// This produces no invocation, request, Run, current authority or Provider I/O.
fn restore_client_effect_original_infer(
  prepared : PreparedClientEffectComputation,
  input : (String, String)?,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientInferPlanGraph?, ClientEffectRunMaterialsIssue] {
  let occurrence = prepared_client_effect_infer_occurrence(prepared)
  let missing = ClientEffectRunMaterialsIssue::Input(
    MaterialsEvidence("infer_execution_contract"),
  )
  match (occurrence, input) {
    (None, None) => Ok(None)
    (Some(occurrence), Some((cid, wire))) => {
      let execution = match
        read_client_infer_occurrence_model_execution(
          occurrence,
          @utf8.encode(wire),
          cid,
          {
            max_bytes: 65536,
            max_nodes: 4096,
            max_depth: 64,
            max_members: 256,
          },
          1000000,
        ) {
        Ok(value) => value
        Err(_) => return Err(missing)
      }
      match
        issue_installed_client_composed_infer_plan_graph(
          occurrence,
          execution,
          limits.sequence,
          limits.max_evidence_bytes,
          limits.max_evidence_nodes,
          limits.max_evidence_depth,
        ) {
        Ok(value) => Ok(Some(value))
        Err(_) => Err(missing)
      }
    }
    _ => Err(missing)
  }
}

///|
fn client_effect_original_infer_inputs(
  compilation : ClientEffectCompilation,
) -> Result[String?, ClientEffectRunMaterialsIssue] {
  if compilation.compiled.infers.length() <= 1 { return Ok(None) }
  guard client_effect_compilation_infer_originals(compilation) is Some(originals) else {
    return Err(Compilation(ForeignInferOwner))
  }
  let limits : ClientValuesRunMaterialsLimits = {
    preparation: client_standard_program_preparation_limits(),
    sequence: client_standard_values_sequence_limits(),
    max_sequence_steps: 1000,
    max_sequence_work: 10000,
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
    max_evidence_depth: 100,
  }
  encode_client_infer_original_inventory(originals.map(value => value.1), compilation.compiled.infers, limits)
    .map(value => Some(value)).map_err(_ => Input(MaterialsEvidence("infer_execution_contracts")))
}
