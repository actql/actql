///|
// Same original definition/invocation must select the capture before Host
// maps or copied nominal inventories are constructed. Slots price only actual
// reference holders; they are neither entry authority nor a byte/count grant.
pub fn reserve_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  slots : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    owner.publication_definition is Some(original_definition) &&
    owner.publication_invocation is Some(original_invocation) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !physical_equal(definition, original_definition) ||
    !physical_equal(invocation, original_invocation) ||
    control.dependency_inventory is None ||
    control.dependency_capture_slots is Some(_) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    slots < 0 {
    return Err(ForeignOriginal)
  }
  guard installed_effect_dependency_fixed_capacity(slots, 0, 64) is Some(fixed) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.dependency_capture_slots = Some(slots)
      Ok(())
    }
  }
}

///|
// The complete prepared semantic inventory is reused. All other original
// occurrences retain their independent nominal checks in the existing issuer.
pub fn begin_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  sources : Array[@publication.CapturedEffectSourceArtifact],
  local_sources : Array[@publication.CapturedLocalEffectSourceEvidence],
  advances : Array[@publication.PendingSourceStateAdvance],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
  preview : @publication.EffectPreviewIdentity,
  plan_names : Array[String],
  plan_wires : Array[String],
  dependency_wire : String,
  content_generations : Array[@publication.BoundContentGeneration],
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
) -> Result[
  @publication.CapturedRunIssuancePreparation,
  ClientInstalledManagedRunIssue,
] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inventory is Some(inventory) &&
    control.dependency_inventory_geometry is Some(geometry) &&
    control.dependency_capture_slots is Some(reserved_slots) &&
    control.dependency_capture is None &&
    owner.publication_definition is Some(original_definition) &&
    owner.publication_invocation is Some(original_invocation) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let slots = definitions.length().to_int64() +
    artifacts.length().to_int64() +
    snapshots.length().to_int64() +
    sources.length().to_int64() +
    local_sources.length().to_int64() +
    advances.length().to_int64() +
    models.length().to_int64() +
    content_generations.length().to_int64() +
    2L * plan_names.length().to_int64()
  if !physical_equal(plan, expected_plan) ||
    !physical_equal(definition, original_definition) ||
    !physical_equal(invocation, original_invocation) ||
    slots > reserved_slots.to_int64() ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) {
    return Err(ForeignOriginal)
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let capture_plan = match
    with_installed_effect_dependency_work(
      control,
      admission,
      plan,
      ledger,
      () => {
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        )
      },
      control.reservation,
      () => owner.effect_operation_opening && !owner.effect_operation_closing,
      spend => {
        let work = fn(units : Int) -> Bool {
          match spend(units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }
        if !work(dependency_wire.length()) ||
          dependency_wire !=
          @publication.captured_effect_dependency_inventory_json(inventory) {
          return Err(
            @resources.NodeManagedRunOperationIssue::Original(ForeignOriginal),
          )
        }
        match
          @publication.prepare_original_effectful_capture_plan(
            definition, invocation, definitions, artifacts, manifest, receipt, snapshots,
            sources, local_sources, advances, authoring, models, preview, plan_names,
            plan_wires, inventory, geometry, content_generations, max_body_bytes,
            max_body_nodes, max_body_depth, work,
          ) {
          Some(value) => Ok(value)
          None =>
            Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
        }
      },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => installed_effect_operation_reservation_issue(issue)
        },
      )
  }
  // The size plan owns only already funded reference copies. If numeric grow
  // fails, cut those aliases while retaining the original failed prefix.
  guard @publication.capture_construction_layout_facts(capture_plan)
    is Some((bytes, nodes, depth, _, _, _, _, _)) &&
    installed_effect_dependency_body_capacity({
      bytes,
      nodes,
      depth,
      arrays: nodes,
      objects: nodes,
      fields: nodes - 1,
      largest_object: nodes - 1,
      strings: nodes,
      text_units: bytes,
    })
    is Some(capacity) else {
    @publication.cancel_capture_construction_plan(capture_plan)
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, capacity,
    ) {
    Err(issue) => {
      @publication.cancel_capture_construction_plan(capture_plan)
      return Err(issue)
    }
    Ok(_) => ()
  }
  guard @publication.start_planned_captured_run(capture_plan) is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  control.dependency_capture = Some(issuer)
  Ok(issuer)
}

///|
pub fn advance_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  issuer : @publication.CapturedRunIssuancePreparation,
  quantum : Int,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else { return Err(ForeignOriginal) }
  if owner.effect_operation_opening || owner.effect_operation_closing { return Err(AlreadyBound) }
  owner.effect_operation_opening = true
  defer { owner.effect_operation_opening = false }
  guard owner.preparation is Some(preparation) && preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) && owner.effect_operation_controls is Some(control) &&
    control.dependency_capture is Some(original_issuer) && physical_equal(original_issuer, issuer) else { return Err(Retired) }
  match check_installed_effect_managed_run_binding(owner, prepared, request) { Err(issue) => return Err(issue); Ok(_) => () }
  if !physical_equal(plan, expected_plan) || quantum < 1 || quantum > 256 { return Err(ForeignOriginal) }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let result = with_installed_effect_dependency_work(control, admission, plan, ledger,
    () => check_installed_effect_operation_original(owner, ledger, preparation, Some(control)), control.reservation,
    () => owner.effect_operation_opening && !owner.effect_operation_closing,
    spend => {
      match issuer.advance_with_work(quantum, units => { match spend(units) { Ok(_) => true; Err(issue) => { refused.val = Some(issue); false } } }) {
        Ok((done, _)) => Ok(done)
        Err(_) => Err(@resources.NodeManagedRunOperationIssue::Original(Unsupported))
      }
    }).map_err(installed_effect_operation_reservation_issue)
  match result { Err(issue) => Err(match refused.val { Some(issue) => Ledger(issue); None => issue }); Ok(value) => Ok(value) }
}

///|
pub fn finish_installed_effect_dependency_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  issuer : @publication.CapturedRunIssuancePreparation,
) -> Result[@publication.PreparedCapturedEffectRun, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else { return Err(ForeignOriginal) }
  if owner.effect_operation_opening || owner.effect_operation_closing { return Err(AlreadyBound) }
  owner.effect_operation_opening = true
  defer { owner.effect_operation_opening = false }
  guard owner.preparation is Some(preparation) && preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) && owner.effect_operation_controls is Some(control) &&
    control.dependency_inventory is Some(inventory) && control.dependency_capture is Some(original_issuer) &&
    physical_equal(original_issuer, issuer) else { return Err(Retired) }
  match check_installed_effect_managed_run_binding(owner, prepared, request) { Err(issue) => return Err(issue); Ok(_) => () }
  if !physical_equal(plan, expected_plan) { return Err(ForeignOriginal) }
  with_installed_effect_dependency_work(control, admission, plan, ledger,
    () => check_installed_effect_operation_original(owner, ledger, preparation, Some(control)), control.reservation,
    () => owner.effect_operation_opening && !owner.effect_operation_closing,
    spend => {
      match spend(1) { Err(issue) => return Err(Control(issue)); Ok(_) => () }
      let captured = match issuer.finish() { Ok(value) => value; Err(_) => return Err(Original(Unsupported)) }
      // Existing binder compares canonical inventory/root text once. Debit
      // the exact completed borrowed wire span before those synchronous walks.
      let wire = @publication.publication_contract_json(captured)
      for _ in 0..<8 { match spend(wire.length()) { Err(issue) => return Err(Control(issue)); Ok(_) => () } }
      match @publication.bind_prepared_captured_effect_run(captured, inventory) {
        Ok(value) => Ok(value)
        Err(_) => Err(Original(ForeignOriginal))
      }
    }).map_err(installed_effect_operation_reservation_issue)
}
