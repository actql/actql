///|
// An optional first-admission loan on the existing Request reservation. No
// Root field, Ledger, authority, Run identity or additional compiler is issued.
// Only this Request owner can adopt it; explicit return retains lower cleanup.
struct ClientRequestOriginalExplanation[I] {
  mut original : (
    ClientRequestPreparation[I],
    I,
    @publication_host.PreparedClientProgram,
    @publication_host.ClientRunCompilation,
  )?
  mut holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]?
  mut adopted : ClientInstalledManagedRun?
  retained : Int64
  execution : Int64
  bytes : Int
  nodes : Int
  depth : Int
}

///|
// Optional Node first-admission wrapper coexistence, in addition to the Core
// token below: producer context + captured method record (2H/8R/4W), six
// conditional links on existing producer/Plan/ticket/issuance records (6R),
// ten argument arrays/27 slots and their length words (10H/27R/10W), bridge
// tuple/Result alternatives (6H/8R), two Facts wrappers (2H/2R), descriptor
// map/data descriptor (2H/2R/3W), one key array (1H/1R/1W), and the native
// Journal close observation (1H/4W). Sequential ACK and unacknowledged-close
// alternatives are conservatively co-counted. No payload String is copied.
let request_original_explanation_node_control_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 24L,
    reference_slots: 54L,
    scalar_words: 22L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// The optional token/Some/original tuple, its adoption Some, complete bounds
// and extent scalars, working reserve closure and callback result cells.
// This is in addition to the existing complete capture constructor census;
// the two owners coexist while the SAME loan moves into the capture scope.
let request_original_explanation_control_bytes : Int64 = request_original_explanation_node_control_bytes +
  @execution.preparation_representation_cost({
    record_headers: 8L,
    reference_slots: 22L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()

///|
fn[I] request_original_explanation_current(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  artifact : @publication_host.ClientRunCompilation,
) -> Bool {
  owner.phase == Selecting &&
  owner.input is Some(original) &&
  physical_equal(original, input) &&
  owner.compiled_program is Some(body) &&
  physical_equal(body, prepared) &&
  owner.program_compilation is Some(compilation) &&
  physical_equal(compilation, artifact)
}

///|
fn[I] reserve_request_original_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  artifact : @publication_host.ClientRunCompilation,
  base_r : Int64,
  base_e : Int64,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ClientOriginalExplanationCaptureIssue] {
  guard request_original_explanation_current(owner, input, prepared, artifact) &&
    owner.program_capacity is Some(capacity) else {
    return Err(ForeignOriginal)
  }
  let extra = request_original_explanation_control_bytes
  guard @execution.checked_preparation_add_product(base_r, extra, 1L)
    is Some(base_r) &&
    @execution.checked_preparation_add_product(base_e, extra, 1L)
    is Some(base_e) &&
    @execution.checked_preparation_add_product(base_r, retained, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(base_e, execution, 1L) is Some(e) else {
    return Err(ConstructionUnavailable)
  }
  let (current_r, current_e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let r = Int64::max(r, current_r)
  let e = Int64::max(e, current_e)
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  if !request_original_explanation_current(owner, input, prepared, artifact) {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
// This entire synchronous measurement frame has returned before a declined
// optional attempt can reconcile its original working extent. No measuring
// writer, callback cell, geometry or semantic token survives that scratch cut.
fn[I] measure_request_original_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  artifact : @publication_host.ClientRunCompilation,
  base_r : Int64,
  base_e : Int64,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[(Int64, Int64), ClientOriginalExplanationCaptureIssue] {
  let entry = explanation_capture_entry_control_bytes
  guard client_static_plan_measurement_construction_bytes(depth)
    is Some(plan_measurement) &&
    explanation_capture_measurement_bytes(bytes) is Some(facts_measurement) &&
    @execution.checked_preparation_add_product(entry, plan_measurement, 1L)
    is Some(controls) &&
    @execution.checked_preparation_add_product(controls, facts_measurement, 1L)
    is Some(controls) else {
    return Err(ConstructionUnavailable)
  }
  match
    reserve_request_original_explanation(
      owner, input, prepared, artifact, base_r, base_e, controls, controls,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let mut carrier = None
  let mut refusal = None
  let geometry = match
    @publication_host.measure_client_pure_compilation_static_plan_view(
      artifact,
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
        match
          reserve_request_original_explanation(
            owner, input, prepared, artifact, base_r, base_e, controls, execution,
          ) {
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
  match
    reserve_request_original_explanation(
      owner, input, prepared, artifact, base_r, base_e, controls, controls,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let facts = match
    @publication_host.measure_client_pure_compilation_explanation_facts(
      artifact, prepared, bytes, nodes, depth,
    ) {
    Err(issue) => return Err(Facts(issue))
    Ok(value) => value
  }
  guard explanation_capture_projection_budget(
      geometry, carrier, facts, controls,
    )
    is Some((retained, execution)) else {
    return Err(ConstructionUnavailable)
  }
  match
    reserve_request_original_explanation(
      owner, input, prepared, artifact, base_r, base_e, retained, execution,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => {
      guard owner.program_capacity is Some(capacity) &&
        @resources.preparation_capacity_working_extents(capacity, input)
        is Ok((r, e)) &&
        r >= base_r &&
        e >= base_e &&
        r - base_r >= request_original_explanation_control_bytes &&
        e - base_e >= request_original_explanation_control_bytes else {
        return Err(ForeignOriginal)
      }
      Ok(
        (
          r - base_r - request_original_explanation_control_bytes,
          e - base_e - request_original_explanation_control_bytes,
        ),
      )
    }
  }
}

///|
// Only an optional feature's own known construction/extent refusal can leave
// the legal Run on its old path. Current loss, reentry and primary Resource
// failures are never absence; they keep normal admission/cleanup semantics.
fn request_original_explanation_optional_refusal(
  issue : ClientOriginalExplanationCaptureIssue,
) -> Bool {
  match issue {
    ConstructionUnavailable
    | Capacity(Resource(RetentionLimit | ExecutionLimit))
    | Plan(UnsupportedCompilation)
    | Plan(Projection(InvalidReadLimits))
    | Facts(InvalidReadLimits)
    | Facts(Encoding(@encode.OutputLimit))
    | Facts(OriginalPlan(UnsupportedCompilation)) => true
    _ => false
  }
}

///|
/// Optional structural metadata on the SAME still-working Request/Plan owner.
/// Call after its original compilation, before module completion/adoption. A
/// known quote refusal disposes measurement first, then restores the original
/// working debit under actual current. No projection/key/IO has started then.
pub fn[I] prepare_request_original_explanation(
  owner : ClientRequestPreparation[I],
  input : I,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  ClientRequestOriginalExplanation[I]?,
  ClientOriginalExplanationCaptureIssue,
] {
  guard owner.phase == ProgramPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(artifact) else {
    return Err(ForeignOriginal)
  }
  if bytes < 1 || nodes < 1 || depth < 1 {
    return Err(InvalidReadLimits)
  }
  let (base_r, base_e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  let entry = explanation_capture_entry_control_bytes +
    request_original_explanation_control_bytes
  guard @execution.checked_preparation_add_product(base_r, entry, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(base_e, entry, 1L) is Some(e) else {
    return Ok(None)
  }
  owner.phase = Selecting
  // Admit even the quotation controls BEFORE constructing the dynamic frame.
  let entry_result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  ).map_err(issue => ClientOriginalExplanationCaptureIssue::Capacity(issue))
  let result = match entry_result {
    Err(issue) => Err(issue)
    Ok(_) =>
      measure_request_original_explanation(
        owner, input, prepared, artifact, base_r, base_e, bytes, nodes, depth,
      )
  }
  let result = match result {
    Err(issue) if request_original_explanation_optional_refusal(issue) =>
      // No new semantic context/borrow exists yet; the measurement frame has
      // returned. Reconciliation itself remains current-sensitive and fallible.
      match
        @resources.reconcile_current_working_preparation_phase(
          capacity, input, base_r, base_e,
        ) {
        Err(cleanup) => Err(Cleanup(issue, cleanup))
        Ok(_) =>
          if request_original_explanation_current(
              owner, input, prepared, artifact,
            ) {
            Ok(None)
          } else {
            Err(ForeignOriginal)
          }
      }
    Err(issue) => Err(issue)
    Ok((retained, execution)) => {
      let (r, e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      match
        @resources.reserve_preparation_construction_input(
          capacity, input, prepared, r, e,
        ) {
        Err(issue) => Err(Capacity(issue))
        Ok(holder) =>
          Ok(
            Some({
              original: Some((owner, input, prepared, artifact)),
              holder: Some(holder),
              adopted: None,
              retained,
              execution,
              bytes,
              nodes,
              depth,
            }),
          )
      }
    }
  }
  if owner.phase == Selecting {
    owner.phase = ProgramPlanReserved
  }
  result
}

///|
/// Read only the Plan facet of this SAME working Request's admitted original.
/// No Run, module/provider, Facts emission or adopted capture is constructed.
/// The complete existing Plan/map/codec quotation remains held by this loan.
pub fn[I] request_original_static_plan_wire(
  value : ClientRequestOriginalExplanation[I],
) -> Result[String, ClientOriginalExplanationCaptureIssue] {
  guard value.original is Some((owner, input, prepared, artifact)) &&
    value.adopted is None &&
    value.holder is Some(holder) &&
    owner.phase == ProgramPlanReserved &&
    !@resources.preparation_body_retirement_started(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard request_original_explanation_current(
        owner, input, prepared, artifact,
      ) else {
        return Err(ForeignOriginal)
      }
      match refresh_request_original_static_plan(owner, input) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard value.original is Some(_) &&
        request_original_explanation_current(owner, input, prepared, artifact) else {
        return Err(ForeignOriginal)
      }
      let wire = match
        @publication_host.client_pure_compilation_static_plan_view(
          artifact,
          prepared,
          value.bytes,
          value.nodes,
          value.depth,
        ) {
        Err(issue) => return Err(Plan(issue))
        Ok(value) => value
      }
      match refresh_request_original_static_plan(owner, input) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard value.original is Some(_) &&
        value.holder is Some(current_holder) &&
        physical_equal(current_holder, holder) &&
        @resources.preparation_body_borrow_value(holder) is Some(current_body) &&
        physical_equal(current_body, prepared) &&
        request_original_explanation_current(owner, input, prepared, artifact) else {
        return Err(ForeignOriginal)
      }
      Ok(wire)
    },
    () => if owner.phase == Selecting { owner.phase = ProgramPlanReserved },
  )
}

///|
// Revalidate this SAME held working debit before/after projection. Reconciling
// to its actual existing extent checks the imported parent and fences reentry;
// it supplies no allowance, quote, reservation or success-by-absence fallback.
fn[I] refresh_request_original_static_plan(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientOriginalExplanationCaptureIssue] {
  guard owner.program_capacity is Some(capacity) else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  @resources.reconcile_current_working_preparation_phase(capacity, input, r, e).map_err(issue => {
      ClientOriginalExplanationCaptureIssue::Capacity(issue)
    },
  )
}

///|
/// Dispose this optional loan explicitly. No first durable ACK is implied.
/// Lower pending cleanup remains on its original token/owner, never a retry of
/// a consumed semantic context or a new capacity source.
pub fn[I] return_request_original_explanation(
  value : ClientRequestOriginalExplanation[I],
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  value.original = None
  value.adopted = None
  match value.holder {
    None => Ok(false)
    // Retain token-only cleanup identity on a declined lower return. Its
    // semantic data has already been cleared; the existing owner may retry
    // retirement autonomously, and explicit repeats never restore a loan.
    Some(holder) =>
      match @resources.return_preparation_body_borrow(holder) {
        Err(BorrowReturned) => Ok(false)
        result => result
      }
  }
}

///|
/// The existing Request owner issues the Run and binds its optional original
/// loan in the SAME synchronous adoption. A later caller cannot attach a token
/// to a foreign Run merely because compiler/Plan identities compare equal.
pub fn[I] begin_request_program_managed_run_with_explanation(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
  value : ClientRequestOriginalExplanation[I],
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard value.original is Some((original, input, prepared, artifact)) &&
    physical_equal(original, owner) &&
    value.adopted is None &&
    value.holder is Some(holder) &&
    !@resources.preparation_body_retirement_started(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    owner.input is Some(current_input) &&
    physical_equal(current_input, input) &&
    owner.program_source_free is Some(plan) &&
    plan.compilation is Some(current_artifact) &&
    physical_equal(current_artifact, artifact) else {
    return Err(ForeignOriginal)
  }
  match begin_request_program_managed_run(owner, request) {
    Err(issue) => Err(issue)
    Ok(run) => {
      value.adopted = Some(run)
      Ok(run)
    }
  }
}

///|
/// Consume the pre-admitted original loan into its SAME adopted Run capture.
/// The borrowed token moves once, rather than allocating another reservation
/// or releasing the first loan before a replacement could retain its debt.
pub fn[I] capture_request_original_explanation(
  value : ClientRequestOriginalExplanation[I],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[
  ClientOriginalExplanationCapture,
  ClientOriginalExplanationCaptureIssue,
] {
  guard value.original is Some((_, _, prepared, artifact)) &&
    value.adopted is Some(run) &&
    value.holder is Some(holder) &&
    !@resources.preparation_body_retirement_started(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(body, prepared) &&
    installed_managed_run_compilation_original(run, prepared)
    is Some(current_artifact) &&
    physical_equal(current_artifact, artifact) &&
    @publication_host.client_compiled_run_matches_pure_compilation(
      compiled, prepared, artifact,
    ) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) &&
    managed_run_publication_body(run, prepared) is Ok(current_holder) else {
    return Err(ForeignOriginal)
  }
  if run.source_free_opening {
    return Err(Capacity(WorkActive))
  }
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(current_holder) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  if r < value.retained || e < value.execution {
    return Err(ConstructionUnavailable)
  }
  run.source_free_opening = true
  match
    @resources.reserve_preparation_publication_phase(
      current_holder, prepared, r, e,
    ) {
    Err(issue) => {
      run.source_free_opening = false
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  guard value.original is Some(_) &&
    value.holder is Some(original_holder) &&
    physical_equal(original_holder, holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(current_body) &&
    physical_equal(current_body, prepared) &&
    managed_run_publication_body(run, prepared) is Ok(_) else {
    run.source_free_opening = false
    return Err(ForeignOriginal)
  }
  let controls = match
    client_static_plan_measurement_construction_bytes(value.depth) {
    None => {
      run.source_free_opening = false
      return Err(ConstructionUnavailable)
    }
    Some(plan_measurement) => {
      guard explanation_capture_measurement_bytes(value.bytes)
        is Some(facts_measurement) &&
        @execution.checked_preparation_add_product(
          explanation_capture_entry_control_bytes, plan_measurement, 1L,
        )
        is Some(controls) &&
        @execution.checked_preparation_add_product(
          controls, facts_measurement, 1L,
        )
        is Some(controls) else {
        run.source_free_opening = false
        return Err(ConstructionUnavailable)
      }
      controls
    }
  }
  let capture : ClientOriginalExplanationCapture = {
    holder,
    original: Some((run, prepared, compiled)),
    // Preserve every later module/adoption increment and the token's own
    // coexistence cost. Only this capture's already-admitted extent is reused.
    base_retained: r - value.retained,
    base_execution: e - value.execution,
    held_retained: r,
    held_execution: e,
    plan_view: None,
    facts: None,
    dispatch_failure_observed: false,
  }
  value.holder = None
  value.original = None
  value.adopted = None
  let constructed = match
    construct_original_explanation_capture(
      capture,
      controls,
      value.bytes,
      value.nodes,
      value.depth,
    ) {
    Ok(_) =>
      reconcile_original_explanation_measurement_scratch(capture, value.bytes)
    Err(issue) => Err(issue)
  }
  let result = match constructed {
    Ok(_) => Ok(capture)
    Err(primary) =>
      match return_installed_original_explanation_capture(capture) {
        Err(cleanup) => Err(Cleanup(primary, cleanup))
        Ok(_) => Err(primary)
      }
  }
  run.source_free_opening = false
  result
}
