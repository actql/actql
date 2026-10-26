///|
/// Reserved continuation, not another token. Its plan is consumed or cleared
/// before the original preparation's last borrower can release capacity.
struct ClientProgramCapture[I] {
  publication : ClientProgramPublication[I]
  mut plan : @publication.CapturedRunConstructionPlan?
  mut issuer : @publication.CapturedRunIssuancePreparation?
  mut validation : ClientProgramValidation[I]?
  mut validation_retained : Int64
}

///|
fn[I] clear_program_publication(
  owner : ClientClosedValuesPreparation[I],
) -> Unit {
  if owner.publication is Some(value) {
    cancel_active_program_snapshot(value)
    value.run = None
    value.completed_snapshots.clear()
  }
  if owner.publication is Some(value) && value.capture is Some(capture) {
    if capture.validation is Some(validation) {
      cancel_program_validation(validation)
    }
    if capture.plan is Some(plan) {
      @publication.cancel_capture_construction_plan(plan)
    }
    capture.plan = None
    if capture.issuer is Some(issuer) {
      issuer.cancel()
    }
    capture.issuer = None
    value.capture = None
  }
}

///|
/// Own the four inventories before measuring, fund their storage before copy,
/// then fund the exact original plan's constructor before returning its handle.
/// Only the fixed publication continuation supplies these nominal originals.
pub fn[I] prepare_program_capture(
  value : ClientProgramPublication[I],
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
) -> Result[ClientProgramCapture[I], ClientClosedValuesPreparationIssue] {
  let owner = value.owner
  guard publication_original_body(value) is Some(prepared) &&
    owner.input is Some(input) &&
    owner.publication_definition is Some(original_definition) &&
    physical_equal(original_definition, definition) &&
    owner.publication_invocation is Some(original_invocation) &&
    physical_equal(original_invocation, invocation) else {
    return Err(ForeignOriginal)
  }
  if value.capture_started ||
    value.snapshot_starting ||
    value.snapshot is Some(_) {
    return Err(WrongPhase)
  }
  guard value.run is Some(run) else { return Err(ForeignOriginal) }
  let expected = @strategy.graph_result_count(@strategy.captured_dag_graph(run))
  if snapshots.length() != expected ||
    value.completed_snapshots.length() != expected {
    return Err(WrongPhase)
  }
  for index in 0..<expected {
    if !physical_equal(snapshots[index], value.completed_snapshots[index]) {
      return Err(ForeignOriginal)
    }
  }
  value.capture_started = true
  let slots = definitions.length().to_int64() +
    artifacts.length().to_int64() +
    snapshots.length().to_int64() +
    models.length().to_int64()
  // Four copied Array wrapper/backing pairs; conservative8+2L backing per
  // inventory, no row/value copying. Fixed Plan/inputs616 are already reserved.
  let arrays = 480L + 16L * slots
  if arrays > 9223372036854775807L - owner.retained_quote {
    return Err(Policy)
  }
  let array_retained = owner.retained_quote + arrays
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      array_retained,
      owner.execution_quote,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => owner.retained_quote = array_retained
  }
  guard publication_original_body(value) is Some(_) else {
    return Err(ForeignOriginal)
  }
  let current_slots = definitions.length().to_int64() +
    artifacts.length().to_int64() +
    snapshots.length().to_int64() +
    models.length().to_int64()
  if current_slots > slots || snapshots.length() != expected {
    return Err(WrongPhase)
  }
  for index in 0..<expected {
    if !physical_equal(snapshots[index], value.completed_snapshots[index]) {
      return Err(ForeignOriginal)
    }
  }
  guard @publication.prepare_original_effect_free_capture_plan(
      definition, invocation, definitions, artifacts, manifest, receipt, snapshots,
      authoring, models,
    )
    is Some(plan) else {
    return Err(Policy)
  }
  let capture : ClientProgramCapture[I] = {
    publication: value,
    plan: Some(plan),
    issuer: None,
    validation: None,
    validation_retained: 0L,
  }
  value.capture = Some(capture)
  guard @publication.capture_construction_layout_facts(plan)
    is Some((bytes, _, depth, nodes, results, fields, max_fields, model_count)) &&
    publication_capture_constructor_layout(
      bytes, nodes, depth, results, fields, max_fields, model_count,
    )
    is Some(layout) &&
    @execution.preparation_representation_cost(layout.retained) is Some(r) &&
    @execution.preparation_representation_cost(layout.temporary) is Some(e) else {
    return Err(Policy)
  }
  if r > 9223372036854775807L - array_retained ||
    e > 9223372036854775807L - publication_projection_execution {
    return Err(Policy)
  }
  match reserve_publication_constructor(value, r, e) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard publication_original_body(value) is Some(_) else {
    return Err(ForeignOriginal)
  }
  Ok(capture)
}

///|
pub fn[I] start_program_capture(
  capture : ClientProgramCapture[I],
) -> Result[ClientProgramCapture[I], ClientClosedValuesPreparationIssue] {
  let value = capture.publication
  guard publication_original_body(value) is Some(_) &&
    value.capture is Some(original) &&
    physical_equal(original, capture) &&
    capture.plan is Some(plan) else {
    return Err(ForeignOriginal)
  }
  let owner = value.owner
  guard owner.input is Some(input) &&
    publication_original_body(value) is Some(prepared) else {
    return Err(ForeignOriginal)
  }
  match
    @resources.reserve_preparation_publication_phase(
      owner.capacity,
      input,
      prepared,
      owner.retained_quote,
      owner.execution_quote,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard publication_original_body(value) is Some(_) &&
    value.capture is Some(current_capture) &&
    physical_equal(current_capture, capture) &&
    capture.plan is Some(current_plan) &&
    physical_equal(current_plan, plan) else {
    return Err(ForeignOriginal)
  }
  capture.plan = None
  match @publication.start_planned_captured_run(plan) {
    Some(preparation) => {
      capture.issuer = Some(preparation)
      Ok(capture)
    }
    None => Err(WrongPhase)
  }
}

///|
pub fn[I] advance_program_capture(
  capture : ClientProgramCapture[I],
  quantum : Int,
) -> Result[(Bool, Int), ClientClosedValuesPreparationIssue] {
  guard publication_original_body(capture.publication) is Some(_) &&
    capture.publication.capture is Some(original) &&
    physical_equal(original, capture) else {
    return Err(ForeignOriginal)
  }
  match refresh_publication_original(capture.publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard capture.publication.capture is Some(current) &&
    physical_equal(current, capture) &&
    capture.issuer is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  issuer.advance(quantum).map_err(issue => PublicationCapture(issue))
}

///|
pub fn[I] finish_program_capture(
  capture : ClientProgramCapture[I],
) -> Result[
  @publication.PublicationContract,
  ClientClosedValuesPreparationIssue,
] {
  guard publication_original_body(capture.publication) is Some(_) &&
    capture.publication.capture is Some(original) &&
    physical_equal(original, capture) else {
    return Err(ForeignOriginal)
  }
  match refresh_publication_original(capture.publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard capture.publication.capture is Some(current) &&
    physical_equal(current, capture) &&
    capture.issuer is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  issuer.finish_retained().map_err(issue => PublicationCapture(issue))
}

///|
pub fn[I] cancel_program_capture(capture : ClientProgramCapture[I]) -> Unit {
  if capture.validation is Some(validation) {
    cancel_program_validation(validation)
  }
  if capture.plan is Some(plan) {
    @publication.cancel_capture_construction_plan(plan)
  }
  capture.plan = None
  if capture.issuer is Some(issuer) {
    issuer.cancel()
  }
  capture.issuer = None
}

///|
pub fn[I] program_capture_limits(
  capture : ClientProgramCapture[I],
) -> Result[(Int, Int, Int), ClientClosedValuesPreparationIssue] {
  match refresh_publication_original(capture.publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard capture.issuer is Some(issuer) &&
    @publication.captured_run_preparation_limits(issuer) is Some(limits) else {
    return Err(WrongPhase)
  }
  Ok(limits)
}
