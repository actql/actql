///|
/// Derive the first acceptance candidate from this completed Request/Plan.
/// The Store caller supplies the actual transaction and current Submit frame.
/// The caller retains the original funded Plan borrow through validation.
/// An installed caller may fund the constructor and stage the candidate
/// locally before returning the same borrow. Only success permits use of the
/// staged transport. Neither callback performs a write.
pub fn[I, E] prepare_request_effect_journal_append(
  owner : ClientRequestPreparation[I],
  input : I,
  plan_input : @resources.PreparationBodyBorrow[
    ClientInstalledEffectManagedPlan,
  ],
  materials : @publication_host.ClientEffectRunMaterials,
  snapshot : @publication_host.ClientSavedSubmissionSnapshot,
  profile : @publication_host.ClientLocalRunPolicyProfile,
  retention : @publication.PublicationContract,
  host_adoption_cid : String,
  read_selection_cid : String,
  now : Double,
  max_records : Int,
  scan : (String, String) -> Result[
    @publication_host.ClientJournalPhysicalRow?,
    E,
  ],
  read : (String, String) -> Result[
    @publication_host.ClientJournalPhysicalRow?,
    E,
  ],
  validate_run : (@publication_host.ClientJournalPhysicalRow) -> Result[
    @publication_host.ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  stage_wire? : ((Int64) -> Result[Unit, E], (String) -> Result[Unit, E])? = None,
  indexed_store? : Bool = false,
) -> Result[
  @publication_host.ClientEffectRunJournalAppend,
  @publication_host.ClientRunJournalAppendIssue[E],
] {
  guard owner.phase == EffectBodyReady &&
    owner.compiled_effect is Some(prepared) &&
    physical_equal(prepared, materials.prepared) &&
    owner.effect_plan is Some(plan) &&
    @resources.preparation_body_borrow_value(plan_input) is Some(borrowed) &&
    physical_equal(plan, borrowed) &&
    physical_equal(prepared, plan.prepared) &&
    materials.request is Some(request) &&
    @publication_host.client_request_identity_relation(request, plan.request)
    is @publication_host.SameRequest &&
    request_submitted_intent_original(owner, input) is Some(intent) else {
    return Err(@publication_host.InvalidOriginal)
  }
  fn current() -> Bool {
    owner.phase == EffectBodyReady &&
    @resources.preparation_body_borrow_value(plan_input) is Some(active_plan) &&
    physical_equal(active_plan, plan) &&
    request_submitted_intent_original(owner, input) is Some(active_intent) &&
    physical_equal(active_intent, intent)
  }
  let candidate = match
    @publication_host.prepare_client_effect_run_journal_append(
      snapshot,
      intent,
      materials,
      profile,
      retention,
      host_adoption_cid,
      read_selection_cid,
      now,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      indexed_store~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Store callbacks can refuse or reenter. Preserve their first refusal and
  // stage only while the same active Request and Plan still own this candidate.
  guard current() else { return Err(@publication_host.InvalidOriginal) }
  if stage_wire is Some((fund, stage)) {
    guard @publication_host.client_effect_run_journal_append_wire_workspace(
        candidate,
      )
      is Some(workspace) else {
      return Err(@publication_host.CapacityExceeded)
    }
    match fund(workspace) {
      Err(issue) => return Err(@publication_host.Observation(issue))
      Ok(_) => ()
    }
    guard current() else { return Err(@publication_host.InvalidOriginal) }
    let wire = match
      @publication_host.client_effect_run_journal_append_wire(candidate) {
      Ok(value) => value
      Err(issue) => return Err(@publication_host.Encoding(issue))
    }
    match stage(wire) {
      Err(issue) => return Err(@publication_host.Observation(issue))
      Ok(_) => ()
    }
    guard current() else { return Err(@publication_host.InvalidOriginal) }
  }
  Ok(candidate)
}
