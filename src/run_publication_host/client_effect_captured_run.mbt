///|
pub(all) enum ClientEffectCapturedRunIssue {
  ForeignInput
  Plan(@strategy.CapturedEffectPlanIssue)
  Proof(@strategy.CapturedEffectPlanInventoryIssue)
  Encoding
}

///|
/// Prepare the existing Captured Run from an actual checked Preview and its
/// verified row plans. Emit plan bodies from the checked terminal rather than
/// accepting caller-authored plans. Persistence, waiting and approval remain
/// separate operations; borrowed inputs keep their existing cleanup owners.
pub fn prepare_client_effect_captured_run(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  preview : @strategy.CapturedEffectPreviewInputs,
  proofs : Array[@strategy.CapturedEffectPlanProof],
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  sources : Array[@publication.CapturedEffectSourceArtifact],
  local_sources : Array[@publication.CapturedLocalEffectSourceEvidence],
  inventory : @publication.CapturedEffectDependencyInventory,
  authoring : @publication.RunEvidenceValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  models? : Array[@publication.RunEvidenceValue] = [],
) -> Result[
  @publication.CapturedRunIssuancePreparation,
  ClientEffectCapturedRunIssue,
] {
  let plans : Array[(String, String)] = []
  match
    visit_client_effect_captured_plan_wires(
      materials,
      inputs,
      preview,
      proofs,
      invocation,
      max_fields,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
      (name, wire) => plans.push((name, wire)),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(
    @publication.start_effectful_captured_run(
      materials.run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      snapshots,
      sources,
      local_sources,
      [],
      authoring,
      models,
      @strategy.captured_effect_preview_ledger_identity(preview),
      plans,
      max_bytes,
      max_nodes,
      max_depth,
      max_workspace,
      dependency_inventory=Some(inventory),
    ),
  )
}

///|
/// Emit only the verified original Preview plans. The installed owner can
/// reserve each returned wire before construction and pass the result to its
/// existing planned Captured Run issuer.
pub fn visit_client_effect_captured_plan_wires(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  preview : @strategy.CapturedEffectPreviewInputs,
  proofs : Array[@strategy.CapturedEffectPlanProof],
  invocation : @publication.PublicationContract,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  emit : (String, String) -> Unit,
  before_wire? : ((Int, Int, Int) -> Bool)? = None,
) -> Result[Unit, ClientEffectCapturedRunIssue] {
  if max_bytes < 1 || max_bytes > 16777216 {
    return Err(Encoding)
  }
  let checked_preview = @strategy.captured_effect_preview_owner(preview)
  let run = @effect_binding.effect_program_run_preview_owner(checked_preview)
  if !@strategy.captured_effect_preview_inputs_available(preview) ||
    !@strategy.captured_effect_inputs_match_computation(
      inputs,
      materials.prepared.graph,
    ) ||
    !physical_equal(
      @effect_binding.effect_program_run_static_candidate(run),
      materials.prepared.candidate,
    ) ||
    @publication.publication_contract_identity(
      @effect_binding.effect_program_run_definition(run),
    ) !=
    @publication.publication_contract_identity(materials.run_definition) ||
    @publication.publication_contract_identity(
      @effect_binding.effect_program_run_preview_invocation(checked_preview),
    ) !=
    @publication.publication_contract_identity(invocation) ||
    @strategy.captured_effect_inputs_run_definition_cid(inputs) !=
    Some(@publication.publication_contract_identity(materials.run_definition)) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !physical_equal(materials.compilation.owner, materials.prepared) {
    return Err(ForeignInput)
  }
  let identity = @strategy.captured_effect_preview_ledger_identity(preview)
  let count = @publication.effect_preview_member_count(identity)
  match
    @strategy.check_captured_effect_plan_proofs(
      preview, proofs, max_work, max_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Proof(issue))
  }
  let mut remaining = max_bytes
  for index in 0..<count {
    guard @strategy.captured_effect_preview_input_at(preview, index)
      is Some(pinned) &&
      @strategy.captured_effect_input_at(
        inputs,
        @strategy.captured_effect_input_member_index(pinned),
      )
      is Some(original) &&
      @strategy.captured_any_result_borrows_share_view(
        @strategy.captured_effect_input_borrow(pinned),
        @strategy.captured_effect_input_borrow(original),
      ) else {
      return Err(ForeignInput)
    }
    let terminal = match
      @strategy.captured_effect_preview_plan_terminal(
        preview, index, max_fields, max_work,
      ) {
      Ok(Some(value)) => value
      Ok(None) => continue
      Err(issue) => return Err(Plan(issue))
    }
    if before_wire is Some(fund) {
      let measured = @encode.measuring_writer(remaining, max_nodes, max_depth) catch {
        _ => return Err(Encoding)
      }
      @stage_results.emit_effect_plan_pipeline(terminal, measured) catch {
        _ => return Err(Encoding)
      }
      let (bytes, nodes, depth) = @encode.finish_measurement_usage(measured) catch {
        _ => return Err(Encoding)
      }
      if !fund(bytes, nodes, depth) {
        return Err(Encoding)
      }
    }
    let writer = @encode.writer(remaining, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    @stage_results.emit_effect_plan_pipeline(terminal, writer) catch {
      _ => return Err(Encoding)
    }
    let (wire, bytes, _, _) = @encode.finish_text_usage(writer) catch {
      _ => return Err(Encoding)
    }
    remaining -= bytes
    guard @publication.effect_preview_member_effect_id(identity, index)
      is Some(name) else {
      return Err(ForeignInput)
    }
    emit(name, wire)
  }
  Ok(())
}
