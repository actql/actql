///|
priv enum StoredMockEffectPreparedCapture {
  PreparingEffectCapture(@publication.CapturedRunIssuancePreparation)
  CompletedEffectCapture(@publication.PreparedCapturedEffectRun)
}

///|
// Use the installed dependency owner and the original bound Preview. The
// draft never supplies authority to act or a durable Checkpoint.
fn advance_original_mock_effect_prepared_capture(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  managed : @local_host.ClientInstalledManagedRun,
  original : MockEffectJournalObservationOriginal,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  dependencies : @publication.CapturedEffectDependencyInventory,
  at : String,
) -> Int {
  let materials = original.journal.materials
  let prepared = materials.prepared
  let request = original.effect.request
  let plan = original.effect.plan
  match targets.prepared_capture {
    Some(CompletedEffectCapture(captured)) => {
      guard physical_equal(
        @publication.prepared_captured_effect_run_inventory(captured),
        dependencies,
      ) else {
        return -32
      }
      return seal_original_mock_effect_review(
        drive, targets, original, publication, captured, at,
      )
    }
    Some(PreparingEffectCapture(issuer)) => {
      match
        @local_host.advance_installed_effect_dependency_capture(
          managed, prepared, request, plan, issuer, 256,
        ) {
        Err(issue) => return mock_effect_work_issue(issue)
        Ok(false) => return 1
        Ok(true) => ()
      }
      match
        @local_host.finish_installed_effect_dependency_capture(
          managed, prepared, request, plan, issuer,
        ) {
        Err(issue) => return mock_effect_work_issue(issue)
        Ok(captured) =>
          targets.prepared_capture = Some(CompletedEffectCapture(captured))
      }
      return 1
    }
    None => ()
  }
  guard targets.workspace is None &&
    targets.bound is Some(bound) &&
    targets.draft is Some(draft) &&
    targets.completed is Some(completed) &&
    targets.captured_sources is Some(sources) &&
    targets.captured_local_sources is Some(locals) &&
    targets.plan_proofs is Some(proofs) &&
    targets.public_manifest is Some(manifest) &&
    targets.public_receipt is Some(receipt) &&
    targets.public_snapshots is Some(snapshots) else {
    return -32
  }
  let count = sources.length()
  let slots = 4L * count.to_int64() +
    manifest.definitions.length().to_int64() +
    manifest.artifacts.length().to_int64() +
    snapshots.length().to_int64()
  if count != targets.members.length() ||
    count != locals.length() ||
    count != proofs.length() ||
    slots > 2147483647L {
    return -32
  }
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  match
    @local_host.reserve_installed_effect_dependency_capture(
      managed,
      prepared,
      request,
      plan,
      materials.run_definition,
      invocation,
      slots.to_int(),
    ) {
    Err(issue) => return mock_effect_work_issue(issue)
    Ok(_) => ()
  }
  let mut fields = 0
  for target in targets.members {
    let next = target.original.write.writable_fields.length()
    if next > 2147483647 - fields {
      return -4
    }
    fields += next
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  guard mock_effect_preview_plan_workspace(fields) is Some(control) &&
    @execution.preparation_array_representation(2L, count.to_int64() * 2L, true)
    is Some(arrays) &&
    @execution.preparation_representation_cost(arrays) is Some(vector_bytes) &&
    @execution.checked_preparation_add_product(control, 1L, vector_bytes)
    is Some(initial) &&
    @resources.reserve_capacity(drive.ledger, 0L, initial) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let names = Array(capacity=count)
  let wires = Array(capacity=count)
  let refused = Ref(false)
  let output_bytes = Ref(0L)
  match
    @host.visit_client_effect_captured_plan_wires(
      materials,
      inputs,
      bound,
      proofs,
      invocation,
      fields,
      limits.max_work,
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
      (name, wire) => {
        names.push(name)
        wires.push(wire)
      },
      before_wire=Some((bytes, nodes, depth) => {
        guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
          is Some(writer) &&
          @execution.preparation_representation_cost({
            record_headers: writer.record_headers,
            reference_slots: writer.reference_slots,
            scalar_words: writer.scalar_words,
            owned_utf16_units: writer.owned_utf16_units,
            owned_wire_bytes: 0L,
          })
          is Some(active) &&
          @execution.checked_preparation_add_product(
            output_bytes.val,
            4L,
            bytes.to_int64(),
          )
          is Some(held) &&
          @execution.checked_preparation_add_product(initial, 1L, held)
          is Some(prev) &&
          @execution.checked_preparation_add_product(prev, 1L, active)
          is Some(peak) &&
          @resources.grow_capacity_reservation(
            drive.ledger,
            workspace,
            0L,
            peak,
          )
          is Ok(_) else {
          refused.val = true
          return false
        }
        output_bytes.val = held
        true
      }),
    ) {
    Err(_) => return if refused.val { -4 } else { -31 }
    Ok(_) => ()
  }
  // The plan writer has returned. Keep its wires and index arrays while
  // the separate Capture constructor grows the original dependency owner.
  guard @execution.checked_preparation_add_product(
      initial,
      1L,
      output_bytes.val,
    )
    is Some(retained) &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      workspace,
      0L,
      retained,
    )
    is Ok(_) else {
    return -9
  }
  match
    @local_host.begin_installed_effect_dependency_capture(
      managed,
      prepared,
      request,
      plan,
      materials.run_definition,
      invocation,
      manifest.definitions,
      manifest.artifacts,
      manifest.manifest,
      receipt,
      snapshots,
      sources,
      locals,
      [],
      draft.authoring,
      [],
      completed.identity,
      names,
      wires,
      @publication.captured_effect_dependency_inventory_json(dependencies),
      [],
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    ) {
    Err(issue) => return mock_effect_work_issue(issue)
    Ok(issuer) =>
      targets.prepared_capture = Some(PreparingEffectCapture(issuer))
  }
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}
