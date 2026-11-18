///|
// A typed borrower of the SAME adopted Request/Run preparation, not a Ledger,
// authorization or durable-ACK issuer. The explicit return drops every new
// semantic alias before lower cleanup can settle the original reservation.
struct ClientOriginalExplanationCapture {
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  mut original : (
    ClientInstalledManagedRun,
    @publication_host.PreparedClientProgram,
    @publication_host.ClientCompiledRun,
  )?
  base_retained : Int64
  base_execution : Int64
  mut held_retained : Int64
  mut held_execution : Int64
  mut plan_view : String?
  mut facts : @publication.RunEvidenceValue?
}

///|
pub(all) enum ClientOriginalExplanationCaptureIssue {
  ForeignOriginal
  InvalidReadLimits
  ConstructionUnavailable
  Capacity(@resources.PreparationCapacityIssue)
  Plan(@publication_host.ClientCompiledRunPlanIssue)
  Facts(@publication_host.ClientExplanationFactsIssue)
  Cleanup(
    ClientOriginalExplanationCaptureIssue,
    @resources.PreparationCapacityIssue
  )
} derive(Eq, Debug)

///|
fn original_explanation_capture_body(
  value : ClientOriginalExplanationCapture,
) -> @publication_host.PreparedClientProgram? {
  guard value.original is Some((run, prepared, compiled)) &&
    managed_run_publication_body(run, prepared) is Ok(_) &&
    installed_managed_run_compilation_original(run, prepared) is Some(artifact) &&
    @publication_host.client_compiled_run_matches_pure_compilation(
      compiled, prepared, artifact,
    ) &&
    !@resources.preparation_body_retirement_started(value.holder) &&
    @resources.preparation_body_borrow_value(value.holder) is Some(body) &&
    physical_equal(body, prepared) else {
    return None
  }
  Some(prepared)
}

///|
// Each phase describes complete coexistence. Retention is monotonic and the
// fixed quotation/measurement controls remain live throughout the first ACK.
// No observed progress shrinks/refills the same reservation or resets debt.
fn reserve_original_explanation_capture(
  value : ClientOriginalExplanationCapture,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ClientOriginalExplanationCaptureIssue] {
  guard original_explanation_capture_body(value) is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  guard @execution.checked_preparation_add_product(
      value.base_retained,
      retained,
      1L,
    )
    is Some(r) else {
    return Err(ConstructionUnavailable)
  }
  let r = Int64::max(r, value.held_retained)
  guard @execution.checked_preparation_add_product(
      value.base_execution,
      execution,
      1L,
    )
    is Some(e) else {
    return Err(ConstructionUnavailable)
  }
  let e = Int64::max(e, value.held_execution)
  guard value.original is Some((run, _, _)) &&
    managed_run_publication_body(run, prepared) is Ok(current_holder) else {
    return Err(ForeignOriginal)
  }
  match
    @resources.reserve_preparation_publication_phase(
      current_holder, prepared, r, e,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard original_explanation_capture_body(value) is Some(current) &&
    physical_equal(current, prepared) else {
    return Err(ForeignOriginal)
  }
  value.held_retained = r
  value.held_execution = e
  Ok(())
}

///|
fn construct_original_explanation_capture(
  value : ClientOriginalExplanationCapture,
  controls : Int64,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, ClientOriginalExplanationCaptureIssue] {
  guard value.original is Some((_, prepared, compiled)) else {
    return Err(ForeignOriginal)
  }
  let mut carrier = None
  let mut refusal = None
  let geometry = match
    @publication_host.measure_client_compiled_run_static_plan_view(
      compiled,
      prepared,
      bytes,
      nodes,
      depth,
      before_carrier_measurement=Some(original => {
        guard @publication_host.client_carrier_measurement_construction(
            original,
            max_depth=depth,
          )
          is Some(data) &&
          client_static_plan_carrier_measurement_layout(data) is Some(layout) &&
          @execution.checked_preparation_add_product(
            controls,
            layout.execution_cost,
            1L,
          )
          is Some(execution) else {
          refusal = Some(ConstructionUnavailable)
          return false
        }
        match reserve_original_explanation_capture(value, controls, execution) {
          Err(issue) => {
            refusal = Some(issue)
            false
          }
          Ok(_) => {
            carrier = Some(
              match carrier {
                None => data
                Some(previous) =>
                  client_static_plan_carrier_construction_max(previous, data)
              },
            )
            true
          }
        }
      }),
    ) {
    Err(issue) => return Err(refusal.unwrap_or(Plan(issue)))
    Ok(value) => value
  }
  guard carrier is Some(carrier) &&
    client_static_plan_carrier_measurement_layout(carrier) is Some(names) &&
    @execution.checked_preparation_add_product(
      controls,
      names.execution_cost,
      2L,
    )
    is Some(controls) else {
    return Err(ConstructionUnavailable)
  }
  // The same checked Carrier recipe includes original reference-name
  // rendering. Conservatively retain two complete alternatives for the two
  // JOIN key names that coexist, not an unrelated spare or new byte grant.
  // This grow precedes every Facts measuring writer/name constructor.
  match reserve_original_explanation_capture(value, controls, controls) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // This original-IR measurement precedes all key/map/Facts constructors. A
  // known quote refusal can therefore be classified at the installed optional
  // feature boundary without turning a stale/current/primary failure into it.
  let facts_geometry = match
    @publication_host.measure_client_compiled_explanation_facts(
      compiled, prepared, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Facts(issue))
    Ok(value) => value
  }
  guard explanation_capture_projection_budget(
      geometry, carrier, facts_geometry, controls,
    )
    is Some((retained, execution)) else {
    return Err(ConstructionUnavailable)
  }
  // view_hold deliberately retains the original parsed view/map, not just the
  // returned String priced by the old static-only reader. It coexists with
  // the complete Facts parser/hash/writer/mandatory validation owner. The
  // identity-free body String passed into seal is separate from the codec's
  // borrowed input and remains live through sealing; price it explicitly.
  match reserve_original_explanation_capture(value, retained, execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (original, wire) = match
    @publication_host.capture_client_structural_explanation_plan_original(
      compiled, prepared, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Facts(issue))
    Ok(value) => value
  }
  let facts = match
    @publication_host.seal_client_structural_explanation_facts(
      original, compiled, prepared, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Facts(issue))
    Ok(value) => value
  }
  guard original_explanation_capture_body(value) is Some(_) else {
    return Err(ForeignOriginal)
  }
  value.plan_view = Some(wire)
  value.facts = Some(facts)
  Ok(())
}

///|
/// First ordinary Plan admission only. The existing adopted Run selects its
/// own retained preparation, request association and actual compiler artifact;
/// callers cannot substitute a bare borrow, Ledger, Boolean or byte allowance.
/// The receiving Journal must keep this loan through its SAME durable ACK,
/// including pending/unknown physical outcomes, and then explicitly return it.
pub fn capture_installed_managed_run_explanation(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  ClientOriginalExplanationCapture,
  ClientOriginalExplanationCaptureIssue,
] {
  // Reuse this SAME owner's synchronous preparation writer fence. A sibling
  // borrow also observes current, outside the lower resize transition itself.
  // No new Normal root slot, scheduler, grant or callback authority is added.
  if run.source_free_opening {
    return Err(Capacity(WorkActive))
  }
  run.source_free_opening = true
  let outcome = capture_installed_original_explanation(
    run, prepared, compiled, definition, bytes, nodes, depth,
  )
  run.source_free_opening = false
  outcome
}

///|
fn capture_installed_original_explanation(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  ClientOriginalExplanationCapture,
  ClientOriginalExplanationCaptureIssue,
] {
  guard installed_managed_run_compilation_original(run, prepared)
    is Some(artifact) &&
    @publication_host.client_compiled_run_matches_pure_compilation(
      compiled, prepared, artifact,
    ) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) else {
    return Err(ForeignOriginal)
  }
  if bytes < 1 || nodes < 1 || depth < 1 {
    return Err(InvalidReadLimits)
  }
  let holder = match managed_run_publication_body(run, prepared) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let (base_retained, base_execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // The fixed quotation forest is a module-original scalar. Back it before
  // constructing even a measuring-writer/codec quotation or its result record.
  let entry = explanation_capture_entry_control_bytes
  if base_retained > 9223372036854775807L - entry ||
    base_execution > 9223372036854775807L - entry {
    return Err(ConstructionUnavailable)
  }
  match
    @resources.reserve_preparation_publication_phase(
      holder,
      prepared,
      base_retained + entry,
      base_execution + entry,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard managed_run_publication_body(run, prepared) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  guard client_static_plan_measurement_construction_bytes(depth)
    is Some(plan_measurement) &&
    explanation_capture_measurement_bytes(bytes) is Some(facts_measurement) &&
    @execution.checked_preparation_add_product(entry, plan_measurement, 1L)
    is Some(controls) &&
    @execution.checked_preparation_add_product(controls, facts_measurement, 1L)
    is Some(controls) &&
    @execution.checked_preparation_add_product(base_retained, controls, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(base_execution, controls, 1L)
    is Some(e) else {
    return Err(ConstructionUnavailable)
  }
  // No new borrower/scope/geometry/writer exists until this second grow.
  // A declined phase keeps already admitted controls charged to the SAME
  // owner; it never fabricates rollback, physical ACK or optional absence.
  match
    @resources.reserve_preparation_publication_phase(holder, prepared, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard managed_run_publication_body(run, prepared) is Ok(_) else {
    return Err(ForeignOriginal)
  }
  let sibling = match @resources.borrow_preparation_body_sibling(holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let value : ClientOriginalExplanationCapture = {
    holder: sibling,
    original: Some((run, prepared, compiled)),
    base_retained,
    base_execution,
    held_retained: r,
    held_execution: e,
    plan_view: None,
    facts: None,
  }
  match
    construct_original_explanation_capture(value, controls, bytes, nodes, depth) {
    Ok(_) => Ok(value)
    Err(primary) =>
      match return_installed_original_explanation_capture(value) {
        Err(cleanup) => Err(Cleanup(primary, cleanup))
        Ok(_) => Err(primary)
      }
  }
}

///|
/// Borrowed immutable first-admission DATA only, not read/egress permission.
/// The caller must not return this capture while either String still awaits
/// the original Journal's durable acknowledgement or physical reconciliation.
pub fn installed_original_explanation_capture_wires(
  value : ClientOriginalExplanationCapture,
) -> Result[(String, String), ClientOriginalExplanationCaptureIssue] {
  guard original_explanation_capture_body(value) is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  guard value.original is Some((run, _, _)) &&
    managed_run_publication_body(run, prepared) is Ok(current_holder) else {
    return Err(ForeignOriginal)
  }
  // Observe SAME original current while the Resource transition fences return
  // and reentry. Do not unwrap/hold the large wire/facts aliases before this
  // boundary. Read actual current debit, never an obsolete smaller quote.
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(current_holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  match
    @resources.reserve_preparation_publication_phase(
      current_holder, prepared, r, e,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard original_explanation_capture_body(value) is Some(current) &&
    physical_equal(current, prepared) &&
    value.plan_view is Some(plan) &&
    value.facts is Some(facts) else {
    return Err(ForeignOriginal)
  }
  Ok((plan, @publication.run_evidence_value_json(facts)))
}

///|
/// Return this metadata loan only; this is NOT a Store/physical-stop ACK. Drop
/// new compiler/map/wire aliases before the existing lower owner can retry or
/// refund. A pending lower return keeps its SAME original retirement duty;
/// repeated return never restores payload or a borrow slot.
pub fn return_installed_original_explanation_capture(
  value : ClientOriginalExplanationCapture,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  value.original = None
  value.plan_view = None
  value.facts = None
  match @resources.return_preparation_body_borrow(value.holder) {
    Err(BorrowReturned) => Ok(false)
    result => result
  }
}
