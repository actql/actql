///|
// Existing binding's unsealed/final text, native evidence and the actual JS
// metadata projection. Future CID extent comes from that SAME original body
// emitter; no receipt, grant or Provider admission is manufactured by sizing.
fn request_model_binding_output_bytes(provider_id : String) -> Int64? {
  guard @publication_host.measure_client_model_provider_binding_construction(
      provider_id,
    )
    is Some(binding) &&
    program_artifact_parse_layout(binding) is Some(parse) &&
    @encode.text_writer_construction_inventory(binding.0, binding.1, binding.2)
    is Some(writer) &&
    @execution.compose_preparation_representation([
      parse.value,
      parse.value,
      parse.temporary,
      {
        record_headers: 2L * writer.record_headers,
        reference_slots: 2L * writer.reference_slots + 1L,
        scalar_words: 2L * writer.scalar_words,
        owned_utf16_units: 2L * writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_representation_cost(peak)
}

///|
/// Same existing provider-binding issuer, reached only after this original
/// Request backs all three contract inputs and complete returned metadata.
/// Original canonical/hash/body checks and the binding's lack of operational
/// authority remain unchanged. Partial failure stays on the same parent.
pub fn[I] prepare_request_model_provider_binding(
  owner : ClientRequestPreparation[I],
  input : I,
  provider_id : String,
  installation : String,
  contract : String,
  configuration : String,
) -> Result[@publication.RunEvidenceValue, ClientRequestProgramPlanIssue] {
  match
    prepare_request_model_contract_materials(
      owner,
      input,
      3,
      index => {
        match index {
          0 => installation
          1 => contract
          _ => configuration
        }
      },
      3,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let original_phase = owner.phase
  let prepared : ClientLocalSequenceOwner = match owner.phase {
    ModelPlanReserved => {
      guard owner.compiled_program is Some(original) else {
        return Err(Preparation(ForeignOriginal))
      }
      Pure(original)
    }
    EffectPlanReserved => {
      guard owner.compiled_effect is Some(original) else {
        return Err(Preparation(ForeignOriginal))
      }
      Effect(original)
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard request_model_binding_output_bytes(provider_id) is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let value = match
        @publication_host.issue_client_model_provider_binding(
          provider_id, installation, contract, configuration,
        ) {
        Err(issue) => return Err(ModelBinding(issue))
        Ok(value) => value
      }
      owner.program_domain_quote = None
      owner.phase = original_phase
      Ok(value)
    },
    () => {
      if owner.phase == Selecting {
        owner.phase = if original_phase == EffectPlanReserved {
          EffectBodyFailed
        } else {
          ProgramBodyFailed
        }
      }
    },
  )
}
