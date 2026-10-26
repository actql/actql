///|
/// Original Node-only preparation driver. No dimensions supplied by JavaScript
/// are a resource grant. The fixed selected supplier and nominal policy must
/// agree before this owner can begin; the unstarted admission is retained by
/// its caller before any fallible start/reserve operation.
struct ClientClosedValuesPreparation[I] {
  mut original : ClientClosedValuesPreparation[I]?
  mut input : I?
  initial : @resources.NodePreparationAdmission[I]
  policy : ClientLocalResourcePolicy
  module_containers : @execution.PreparationRepresentationUnits
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ]
  mut work : @resources.PreparationPhaseWork?
  mut header_fields : Int
  mut header_rows : Int
  mut retiring : Bool
  mut module_constructing : Bool
  mut text_checked : Bool
  mut scan_complete : Bool
  mut document : String?
  mut parsed : @syntax.ParsedProgramInput?
  mut program : @syntax.Program?
  mut prepared : @publication_host.PreparedClientProgram?
  mut shape : ClosedValuesShape?
  mut lexical : ClosedValuesLexicalFacts?
  mut envelope : ClientClosedValuesInputEnvelope?
  mut retained_quote : Int64
  mut execution_quote : Int64
  mut compilation : @publication_host.ClientValuesCompilation?
  mut source_free : ClientInstalledManagedSourceFreePreparation?
  mut body_ready : Bool
  mut manager_issued : Bool
  mut adopted_run : ClientInstalledManagedRun?
  mut adopted : Bool
  mut submitted_intent : @publication_host.ClientSubmittedIntent?
  mut publication_invocation_started : Bool
  mut publication_definition : @publication.PublicationContract?
  mut publication_invocation : @publication.PublicationContract?
  mut publication_started : Bool
  mut publication : ClientProgramPublication[I]?
  mut manager_original : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]?
}

///|
pub(all) enum ClientClosedValuesPreparationIssue {
  ForeignOriginal
  WrongPhase
  Policy
  Syntax(@syntax.SyntaxError)
  Preparation(@publication_host.ClientProgramPreparationIssue)
  Installed(ClientInstalledManagedRunIssue)
  Compilation(@publication_host.ClientValuesCompilationIssue)
  Initial(@resources.ImportedChildLedgerIssue)
  Capacity(@resources.PreparationCapacityIssue)
  Work(@resources.PreparationWorkIssue)
  CapacityExceeded(ClientPreparationCapacityRefusal)
  Intent(@publication_host.ClientSubmittedIntentIssue)
  PublicationInvocation(@publication.RunEvidenceValueIssue)
  PublicationCapture(@publication.CapturedRunIssuanceIssue)
  PublicationSnapshot(@publication_host.PublicationOutputExportIssue)
}

///|
/// Fixed request-owned constructor controls, not VM frame/allocator sizes.
/// The selected installation's existing bootstrap recipe covers construction
/// before the child exists; this exact projection is then held on that same
/// child's Ledger, never converted into a second 512 MiB pool.
fn closed_values_initial_control_units(
  module_containers : @execution.PreparationRepresentationUnits,
) -> @execution.PreparationRepresentationUnits {
  // JS: producer + empty receipt; preparation link; empty Resource original;
  // Resource state; six-slot quota Array; weak identity control+entry; ports;
  // six allocated closures with at most state/original captures; SDK wrapper.
  // Additional six arrays: purpose4, quota names6, report validation3/7,
  // old/new live usage5/5. Four callbacks: quota map, two every, stop some.
  // Literal/fixed arrays use exact slots (no append growth); reference entries
  // are the borrowed purpose/name Strings, other entries scalar quantities.
  let js_headers = 3L * 2L +
    2L +
    1L +
    1L +
    1L +
    2L +
    2L +
    1L +
    6L +
    1L +
    2L * 6L +
    4L
  let js_refs = 1L +
    3L * 3L +
    8L +
    6L +
    6L +
    1L +
    1L +
    4L +
    12L +
    2L +
    6L +
    4L +
    6L +
    1L
  let js_words = 1L + 1L + 5L + 2L + 6L + 2L * 6L + 3L + 7L + 2L * 5L
  // Imported origin (six ports), child, Node admission and its initial wrapper.
  // Six port closures + map continuation + abort closure borrow these originals.
  let import_headers = 1L + 1L + 1L + 1L + 8L
  let import_refs = 7L + 8L + 7L + 1L + 9L
  let import_words = 4L + 3L + 4L + 1L
  // Ledger/limits; old+new usage during reserve; three zero QuantityAmounts
  // and QuantityUsage; Reservation, its observed tuple and byte-only wrapper.
  let ledger_headers = 1L + 1L + 2L + 4L + 1L + 1L + 1L
  let ledger_refs = 7L + 3L + 5L + 1L
  // Ledger also retains its one-use continuation-restored scalar.
  let ledger_words = 4L + 6L + 20L + 9L + 6L + 3L
  // PreparationCapacity; driver; live Some identity/ledger/input/serial links.
  // Maximum live work receipts is max(3,1,1), not lifetime issuance count:
  // header/scan/text coexist until the synchronous input callback returns;
  // later snapshot lexical and intent callbacks each own one, with no saved
  // receipt alias from the prior callback. Each has two
  // Ref cells, two closures, one record, active Some and returned Ok carrier.
  let driver_headers = 1L + 1L + 12L + 3L * 7L + 1L
  // The staged compilation slot exists before artifact construction.
  // One extra reference borrows the immutable selected-backend unit recipe.
  let driver_refs = 5L + 15L + 12L + 3L * 10L + 2L + 1L + 1L
  // One synchronous module-constructor latch remains on this original owner.
  let driver_words = 5L + 10L + 12L + 3L * 5L + 1L + 1L
  // Six actual fixed live roles, not a historical issuance limit: manager,
  // registry handler/dispatch, Node admission, Run, configured Host. The Host
  // covers transitive outputs/readers until real drain, not one borrow/output.
  // Per role: generic token/bodySome, erased wrapper/five closures, returned
  // carriers and consumer Some overlap. Handoff adds successor admission,
  // retirement closure/receipt and Run retirement bundle beside old owners.
  // The actual installed Run owns its record/Pure variant, five Some links
  // and two empty arrays. The one graph-match carrier is conservatively held
  // in this retained control majorant through final cleanup (no E grant).
  // Diagnostic scalar tuple/result/bridge packet: no mutable Ledger escape.
  // Refusal DATA: availability tuple/Ok2, refusalrecord/variant/Err3,
  // projection Some/tuple2, JS Error/capacityrecord/four decimalStrings6:
  // thirteen headers, twenty ref/word slots and80UTF16 bound these families.
  // This is charged before the attempt, including a failed constructor.
  // Registry undispatched membership/ref and handlerFinished word are above.
  // Publication-owned fixed controls: four owner reference slots/two flags;
  // four live Some bindings; publication record6refs/7words; run Some;
  // Node thunk+seven propagated refs; installed Run DAG Some/slot/open latch;
  // pre-reservation original checks/resize16H32R24W. Total24H56R40W=1152.
  // Completed-snapshot inventory and per-result wrappers are plan-derived later.
  let diagnostic_headers = 4L + 13L + 24L
  let diagnostic_refs = 2L + 20L + 56L
  let diagnostic_words = 15L + 20L + 40L
  // Fixed ordinary/embedded Run records +empty child Array, weak/live
  // memberships and retirement closure. Check/Reflect argument arrays and
  // predicate closure are held conservatively in this same R majorant.
  // Operation-scoped original intent DATA has3 borrowed references and one
  // incoming operation field; the existing release closure captures one exact
  // operation identity to refuse stale release, clearing its heavy field first.
  let adopted_js_headers = 10L + 1L
  let adopted_js_refs = 48L + 5L
  let adopted_js_words = 9L
  // The common prepared Local packet retains graph, original policy,
  // registry, module and fixed capacity plus the retained-output flag.
  let run_headers = 11L + 1L + 1L
  let run_refs = 18L + 1L + 5L
  let run_words = 14L + 1L + 1L
  // The closed PurePreparation/EffectPlanPreparation custody choice adds one
  // original wrapper header, one reference and its scalar variant tag. Both
  // cases still use the same already counted retirement record and engine.
  let holder_headers = 6L * 12L + 4L + 2L + 1L + 1L
  let holder_refs = 6L * 17L + 10L + 1L + 3L + 1L
  let holder_words = 6L * 6L + 7L + 1L
  // Four snapshot/selection containers for this fixed numeric Values task.
  // Their immutable recipe is supplied by the SAME installed Node/RelA
  // package before initial admission; provider bodies/factory temporaries
  // remain independent demands. No amount supplied by JS selects this recipe.
  let containers = module_containers
  {
    record_headers: js_headers +
    import_headers +
    ledger_headers +
    driver_headers +
    holder_headers +
    run_headers +
    diagnostic_headers +
    adopted_js_headers +
    containers.record_headers,
    reference_slots: js_refs +
    import_refs +
    ledger_refs +
    driver_refs +
    holder_refs +
    run_refs +
    diagnostic_refs +
    adopted_js_refs +
    containers.reference_slots,
    scalar_words: js_words +
    import_words +
    ledger_words +
    driver_words +
    holder_words +
    run_words +
    diagnostic_words +
    adopted_js_words +
    containers.scalar_words,
    owned_utf16_units: 80L + containers.owned_utf16_units,
    owned_wire_bytes: containers.owned_wire_bytes,
  }
}

///|
/// Fixed supplier precondition. It must be checked before creating the new
/// per-request JS controls; it does not itself allocate or create a Ledger.
pub fn client_closed_values_initial_control_capacity(
  policy : ClientLocalResourcePolicy,
  module_containers~ : @execution.PreparationRepresentationUnits,
) -> (Int64, Int64)? {
  guard @execution.preparation_representation_cost(module_containers) is Some(_) &&
    client_local_preparation_initial_limits(policy) is Some(limits) &&
    @execution.preparation_representation_cost(
      closed_values_initial_control_units(module_containers),
    )
    is Some(retained) &&
    preparation_node_own_data_scan_cost() is Some(scan) &&
    preparation_node_own_data_header_cost() is Some(header) &&
    @execution.preparation_representation_cost(
      closed_values_projection_scratch_units(),
    )
    is Some(projection) else {
    return None
  }
  if retained > limits.retained_bytes ||
    header > limits.execution_bytes ||
    scan > limits.execution_bytes - header ||
    projection > limits.execution_bytes - header - scan {
    return None
  }
  Some((retained, scan + header + projection))
}

///|
pub fn[I] begin_closed_values_preparation(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
  module_containers~ : @execution.PreparationRepresentationUnits,
) -> Result[
  ClientClosedValuesPreparation[I],
  ClientClosedValuesPreparationIssue,
] {
  guard client_local_preparation_initial_limits(policy) is Some(expected) &&
    client_closed_values_initial_control_capacity(policy, module_containers~)
    is Some((retained, execution)) else {
    return Err(Policy)
  }
  match @resources.check_node_preparation_input(initial, input) {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => ()
  }
  let ledger = match @resources.start_node_preparation_admission(initial) {
    Ok(value) => value
    Err(issue) => return Err(Initial(issue))
  }
  if @resources.ledger_limits(ledger) != expected {
    return Err(Policy)
  }
  let capacity = match
    @resources.reserve_preparation_capacity(
      ledger,
      input,
      retained,
      execution,
      max_borrowers=6,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  // No fallible constructor follows reservation without returning its owner.
  // The separate fixed header-open call runs only after the caller stores it.
  let value : ClientClosedValuesPreparation[I] = {
    original: None,
    input: Some(input),
    initial,
    policy,
    module_containers,
    capacity,
    work: None,
    header_fields: 0,
    header_rows: 0,
    retiring: false,
    module_constructing: false,
    text_checked: false,
    scan_complete: false,
    document: None,
    parsed: None,
    program: None,
    prepared: None,
    shape: None,
    lexical: None,
    envelope: None,
    retained_quote: retained,
    execution_quote: execution,
    source_free: None,
    compilation: None,
    body_ready: false,
    manager_issued: false,
    adopted: false,
    adopted_run: None,
    submitted_intent: None,
    manager_original: None,
    publication: None,
    publication_started: false,
    publication_invocation_started: false,
    publication_definition: None,
    publication_invocation: None,
  }
  value.original = Some(value)
  Ok(value)
}

///|
pub fn[I] begin_closed_values_header(
  owner : ClientClosedValuesPreparation[I],
) -> Result[@resources.PreparationPhaseWork, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.work is Some(_) || owner.header_fields != 0 || owner.scan_complete {
    return Err(WrongPhase)
  }
  match
    @resources.begin_preparation_phase_work(
      owner.capacity,
      input,
      @resources.HeaderInspection,
      50,
    ) {
    Err(issue) => Err(Work(issue))
    Ok(work) => {
      owner.work = Some(work)
      Ok(work)
    }
  }
}

///|
/// Only the fixed Node adapter supplies F/R read from its private original-
/// input-bound header receipt. These values select finite work, not byte quota.
pub fn[I] begin_closed_values_scan(
  owner : ClientClosedValuesPreparation[I],
  fields : Int,
  rows : Int,
) -> Result[@resources.PreparationPhaseWork, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || owner.header_fields != 0 || owner.scan_complete {
    return Err(WrongPhase)
  }
  guard preparation_node_own_data_scan_work(fields, rows) is Some(maximum) &&
    owner.work is Some(previous) else {
    return Err(WrongPhase)
  }
  match @resources.finish_preparation_phase_work(previous) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => owner.work = None
  }
  match
    @resources.begin_preparation_phase_work(
      owner.capacity,
      input,
      @resources.OwnDataScan,
      maximum,
    ) {
    Err(issue) => Err(Work(issue))
    Ok(work) => {
      owner.header_fields = fields
      owner.header_rows = rows
      owner.work = Some(work)
      Ok(work)
    }
  }
}

///|
pub fn[I] finish_closed_values_scan(
  owner : ClientClosedValuesPreparation[I],
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || owner.header_fields < 1 || owner.scan_complete {
    return Err(WrongPhase)
  }
  guard owner.work is Some(work) else { return Err(WrongPhase) }
  match @resources.finish_preparation_phase_work(work) {
    Err(issue) => Err(Work(issue))
    Ok(_) => {
      owner.work = None
      owner.scan_complete = true
      Ok(())
    }
  }
}

///|
/// Fixed selected callback only, after synchronous constructors and every SDK
/// source/diagnostic alias have unwound or been severed. Cancellation by itself
/// is not this proof. Failure preserves this exact light cleanup receipt.
pub fn[I] abort_closed_values_preparation_after_cleanup(
  owner : ClientClosedValuesPreparation[I],
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.adopted || owner.module_constructing {
    return Err(WrongPhase)
  }
  if owner.work is Some(work) {
    match @resources.finish_preparation_phase_work(work) {
      Err(issue) => return Err(Work(issue))
      Ok(_) => owner.work = None
    }
  }
  owner.document = None
  owner.parsed = None
  owner.program = None
  clear_program_publication(owner)
  owner.publication = None
  owner.adopted_run = None
  owner.publication_definition = None
  owner.publication_invocation = None
  owner.prepared = None
  owner.submitted_intent = None
  owner.source_free = None
  owner.compilation = None
  owner.shape = None
  owner.lexical = None
  owner.envelope = None
  let stopped = if owner.retiring || owner.body_ready {
    owner.retiring = true
    @resources.retire_preparation_capacity(owner.capacity)
  } else {
    guard owner.input is Some(input) else { return Err(ForeignOriginal) }
    owner.retiring = true
    @resources.abort_preparation_capacity_after_cleanup(owner.capacity, input)
  }
  match stopped {
    Err(issue) => return Err(Capacity(issue))
    Ok(false) => return Err(WrongPhase)
    Ok(true) => owner.input = None
  }
  @resources.cleanup_node_preparation_admission(owner.initial).map_err(issue => {
    ClientClosedValuesPreparationIssue::Initial(issue)
  })
}

///|
/// First scan facts bound the second, allocation-free character eligibility
/// pass before SDK cloning. Unsupported text can therefore return to legacy
/// only after the original initial child has actually cleaned up. No text cap.
pub fn[I] begin_closed_values_text_check(
  owner : ClientClosedValuesPreparation[I],
  quoted_utf16_units : Int,
) -> Result[@resources.PreparationPhaseWork, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring ||
    !owner.scan_complete ||
    owner.text_checked ||
    owner.work is Some(_) ||
    quoted_utf16_units < 0 {
    return Err(WrongPhase)
  }
  guard preparation_node_own_data_scan_work(
      owner.header_fields,
      owner.header_rows,
    )
    is Some(scan_work) &&
    quoted_utf16_units <= 2147483647 - scan_work &&
    client_closed_values_initial_control_capacity(
      owner.policy,
      module_containers=owner.module_containers,
    )
    is Some((retained, base_execution)) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 13L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(previous_facts) else {
    return Err(Policy)
  }
  match
    reserve_closed_values_phase(
      owner.capacity,
      input,
      TextEligibility,
      retained,
      base_execution + previous_facts,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => {
      owner.retained_quote = retained
      owner.execution_quote = base_execution + previous_facts
    }
  }
  match
    @resources.begin_preparation_phase_work(
      owner.capacity,
      input,
      @resources.TextEligibility,
      scan_work + quoted_utf16_units,
    ) {
    Err(issue) => Err(Work(issue))
    Ok(work) => {
      owner.work = Some(work)
      Ok(work)
    }
  }
}

///|
/// The fixed character scanner invokes this only on its successful original
/// pass. Common still independently verifies lexical eligibility before parse.
pub fn[I] finish_closed_values_text_check(
  owner : ClientClosedValuesPreparation[I],
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || !owner.scan_complete || owner.text_checked {
    return Err(WrongPhase)
  }
  guard owner.work is Some(work) else { return Err(WrongPhase) }
  match @resources.finish_preparation_phase_work(work) {
    Err(issue) => Err(Work(issue))
    Ok(_) => {
      owner.work = None
      owner.text_checked = true
      Ok(())
    }
  }
}

///|
/// Grow the SAME original reservation before SDK clone/stringify. This covers
/// the SDK value share and its construction overlap, not semantic preparation.
/// Later phases must grow before their own constructors; no numeric JS grant.
pub fn[I] reserve_closed_values_snapshot(
  owner : ClientClosedValuesPreparation[I],
  facts : ClientClosedValuesInputEnvelope,
  consent_refs : Int,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring ||
    !owner.text_checked ||
    owner.work is Some(_) ||
    owner.envelope is Some(_) ||
    facts.fields != owner.header_fields ||
    facts.rows != owner.header_rows {
    return Err(WrongPhase)
  }
  guard closed_values_snapshot_inventories(facts, consent_refs)
    is Some(snapshot) &&
    closed_values_intent_inventories(facts) is Some(intent) &&
    @execution.compose_preparation_representation([
      closed_values_initial_control_units(owner.module_containers),
      snapshot.retained_host_share,
      snapshot.document,
      intent.retained,
      {
        record_headers: 4L,
        reference_slots: 2L,
        scalar_words: 23L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained_units) &&
    @execution.preparation_representation_cost(retained_units) is Some(retained) &&
    @execution.compose_preparation_representation([
      intent.shared_temporary,
      intent.js_temporary,
    ])
    is Some(js_units) &&
    @execution.compose_preparation_representation([
      intent.shared_temporary,
      intent.core_temporary,
    ])
    is Some(core_units) &&
    @execution.preparation_representation_cost(js_units) is Some(js_execution) &&
    @execution.preparation_representation_cost(core_units)
    is Some(core_execution) &&
    @execution.preparation_representation_cost(snapshot.temporary)
    is Some(snapshot_execution) &&
    client_closed_values_initial_control_capacity(
      owner.policy,
      module_containers=owner.module_containers,
    )
    is Some((_, controls)) else {
    return Err(Policy)
  }
  // JS canonical rendering returns its wire before the Common intent engine
  // starts. Only the explicitly shared wire survives, not JS row temporaries.
  // Keep snapshot scratch additive until its separate SDK lifetime is proved.
  let intent_execution = Int64::max(js_execution, core_execution)
  if snapshot_execution > 9223372036854775807L - intent_execution {
    return Err(Policy)
  }
  let temporary = snapshot_execution + intent_execution
  if temporary > 9223372036854775807L - controls - 120L {
    return Err(Policy)
  }
  let execution = temporary + controls + 120L
  match
    reserve_closed_values_phase(
      owner.capacity,
      input,
      SnapshotAndIntent,
      retained,
      execution,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      owner.retained_quote = retained
      owner.execution_quote = execution
      owner.envelope = Some(facts)
      Ok(())
    }
  }
}

///|
/// The document allocation was funded by reserve_snapshot. Retain it before
/// validation so failures preserve custody through the fixed diagnostic unwind.
pub fn[I] bind_closed_values_document(
  owner : ClientClosedValuesPreparation[I],
  document : String,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring || owner.document is Some(_) || owner.work is Some(_) {
    return Err(WrongPhase)
  }
  guard owner.envelope is Some(bounds) else { return Err(WrongPhase) }
  owner.document = Some(document)
  if document.length() > bounds.input_bytes_upper {
    return Err(Policy)
  }
  guard owner.input is Some(input) else { return Err(ForeignOriginal) }
  let work = match
    @resources.begin_preparation_phase_work(
      owner.capacity,
      input,
      @resources.LexicalScan,
      document.length(),
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  owner.work = Some(work)
  match @resources.spend_preparation_phase_work(work, document.length()) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  guard closed_values_lexical_facts(document, document.length()) is Some(facts) else {
    return Err(Policy)
  }
  if facts.node_upper > bounds.node_upper ||
    facts.objects > bounds.objects ||
    facts.arrays > bounds.arrays ||
    facts.fields_upper > bounds.fields_upper ||
    facts.quoted_tokens > bounds.quoted_tokens ||
    facts.quoted_utf16_units > bounds.quoted_utf16_units ||
    facts.depth_upper > bounds.depth_upper {
    return Err(Policy)
  }
  owner.lexical = Some(facts)
  match @resources.finish_preparation_phase_work(work) {
    Err(issue) => Err(Work(issue))
    Ok(_) => {
      owner.work = None
      Ok(())
    }
  }
}
