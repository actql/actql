///|
/// Identity-bearing request admitted before a remote Site may start work.
/// Transport nonces and future execution results are deliberately absent.
struct DispatchRequest {
  coordinator_authority : String
  run_definition_cid : String
  task_key : String
  task_attempt : Int
  dispatch_id : String
  dispatch_request_cid : String
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  input_binding_cid : String
  obligations_cid : String
  budget_cid : String
  evidence_issuer_capability_cid : String
  grant_cid : String
}

///|
/// A pre-provisioned dispatch budget binds exact Site retention and execution
/// capacity before a remote operation can start.
struct RemoteDispatchBudget {
  retained_bytes : Int64
  execution_bytes : Int64
  budget_cid : String
}

///|
/// A Host-registered issuer is scoped to one live Site generation, runtime,
/// Connector revision and evidence kind. Possessing Site identity alone does
/// not authorize every assertion the Site could make.
struct RemoteEvidenceIssuer {
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  evidence_kind : String
  issuer_capability_cid : String
}

///|
/// Execution permission is separate from Site identity and evidence issuance.
/// It is installed by the Host for one exact runtime implementation scope.
struct RemoteExecutionCapability {
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  operation_capability_cid : String
}

///|
/// Durable evidence binds a registered assertion to the exact dispatch and
/// retained material. Its identity is independent from transport encoding and
/// from the logical identity of the result itself.
struct RemoteExecutionEvidence {
  dispatch_request_cid : String
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  obligations_cid : String
  material_generation : String
  holding_evidence_cid : String
  evidence_kind : String
  evidence_subject_cid : String
  issuer_capability_cid : String
  evidence_cid : String
}

///|
/// Canonical subject for one retained managed output. This is the typed claim
/// referenced by execution evidence, not the logical Result identity and not a
/// read grant. The physical manifest binds the ordered encoded representation;
/// the schema, view and profile keep that representation attached to the exact
/// managed-output contract that a common completion will later verify.
struct RemoteManagedOutputSubject {
  dispatch_request_cid : String
  material_generation : String
  holding_evidence_cid : String
  managed_profile_cid : String
  result_schema_cid : String
  logical_view_cid : String
  representation_codec_cid : String
  physical_manifest_cid : String
  measurement_evidence_cid : String
  row_count : Int
  retained_bytes : Int64
  subject_cid : String
}

///|
/// Compact validation and measurement facts for one exact managed output.
/// The record is content-addressed independently from physical integrity and
/// logical identity. It has authority only when referenced by typed execution
/// evidence from a Host-registered implementation.
struct RemoteManagedOutputMeasurement {
  row_count : Int
  admission_nodes : Int
  admission_text_bytes : Int
  admission_work : Int
  column_rows : Array[Int]
  column_bytes : Array[Int]
  column_nodes : Array[Int]
  column_max_value_bytes : Array[Int]
  column_null_rows : Array[Int]
  column_admitted_depths : Array[Int]
  measurement_cid : String
}

///|
/// Physical execution observations and common completion are different facts.
pub(all) enum RemoteExecutionState {
  Accepted
  Provisioning
  Running
  NativeSettled
  ExecutionFailed
  ExecutionCancelled
  ExecutionUnknown
} derive(Eq, Debug)

///|
/// Evidence progression is independent from physical execution progression.
pub(all) enum RemoteEvidenceState {
  NoEvidence
  OutputRetained(String, String)
  EvidenceDurable(String, String, String)
  EvidenceRejected
} derive(Eq, Debug)

///|
/// Holdings and cleanup remain independent from execution and evidence.
pub(all) enum RemoteCleanupState {
  CleanupActive
  CleanupReleasing
  CleanupReleased
  CleanupUnknown
  CleanupForceLost
  CleanupRecoveredAfterLoss
} derive(Eq, Debug)

///|
pub(all) enum DispatchAcceptance {
  NewDispatch
  ExistingDispatch
} derive(Eq, Debug)

///|
pub(all) enum DispatchIssue {
  InvalidJournal
  InvalidDispatch
  ForeignCoordinator
  ForeignSite
  StaleSiteGeneration
  DispatchCollision
  AttemptAlreadyDispatched
  InvalidTransition
  MaterialUnavailable
  UnauthorizedForceLoss
  DispatchIdentityMismatch
  DurabilityUnconfirmed
  StateCollision
  QuarantinedCapacity
} derive(Eq, Debug)

///|
/// A journal record keeps historical facts while current availability changes.
struct DispatchRecord {
  request : DispatchRequest
  mut revision : Int
  mut execution : RemoteExecutionState
  mut evidence : RemoteEvidenceState
  mut cleanup : RemoteCleanupState
  mut material_available : Bool
  mut quarantined_capacity : Bool
}

///|
/// A portable transition plan has no authority until its exact target state
/// is durably installed by the physical journal.
struct DispatchTransition {
  record : DispatchRecord
  expected_revision : Int
  expected_execution : RemoteExecutionState
  expected_evidence : RemoteEvidenceState
  expected_cleanup : RemoteCleanupState
  expected_material_available : Bool
  expected_quarantined_capacity : Bool
  next_execution : RemoteExecutionState
  next_evidence : RemoteEvidenceState
  next_cleanup : RemoteCleanupState
  next_material_available : Bool
  next_quarantined_capacity : Bool
  mut consumed : Bool
}

///|
/// Force loss includes the Site authority that must be revoked after the
/// exact quarantined record state is durable.
struct ForceLossTransition {
  journal : SiteDispatchJournal
  transition : DispatchTransition
}

///|
/// A generation restart is one durable metadata transition plus the exact
/// record transitions made unknown by loss of the old Agent process.
struct SiteRestartTransition {
  journal : SiteDispatchJournal
  replacement : @site.ExecutionSite
  expected_generation : Int
  transitions : Array[DispatchTransition]
  mut consumed : Bool
}

///|
/// Prepared admission contains no authority to start physical work. A journal
/// adapter must durably install or reconcile the exact request before commit.
struct DispatchAdmission {
  journal : SiteDispatchJournal
  request : DispatchRequest
  acceptance : DispatchAcceptance
  mut consumed : Bool
}

///|
/// The portable journal owns application transitions, not database mechanics.
struct SiteDispatchJournal {
  mut site : @site.ExecutionSite
  protocol_version : String
  dispatches : Map[String, DispatchRecord]
  attempts : Map[String, String]
}

///|
fn nonempty(value : String) -> Bool {
  !value.is_empty()
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn keyed(value : String) -> String {
  value.length().to_string() + ":" + value
}

///|
fn dispatch_key(request : DispatchRequest) -> String {
  keyed(request.coordinator_authority) +
  keyed(request.site_key) +
  request.site_generation.to_string() +
  ":" +
  keyed(request.dispatch_id)
}

///|
fn attempt_key(request : DispatchRequest) -> String {
  keyed(request.coordinator_authority) +
  keyed(request.run_definition_cid) +
  keyed(request.task_key) +
  request.task_attempt.to_string()
}

///|
fn valid_request_fields(request : DispatchRequest) -> Bool {
  nonempty(request.coordinator_authority) &&
  valid_cid(request.run_definition_cid) &&
  nonempty(request.task_key) &&
  request.task_attempt > 0 &&
  nonempty(request.dispatch_id) &&
  nonempty(request.site_key) &&
  request.site_generation >= 0 &&
  valid_cid(request.runtime_bundle_cid) &&
  nonempty(request.connector_registration) &&
  nonempty(request.connector_revision) &&
  nonempty(request.strategy_revision) &&
  valid_cid(request.input_binding_cid) &&
  valid_cid(request.obligations_cid) &&
  valid_cid(request.budget_cid) &&
  valid_cid(request.evidence_issuer_capability_cid) &&
  valid_cid(request.grant_cid)
}

///|
fn valid_request(request : DispatchRequest) -> Bool {
  if !valid_request_fields(request) || !valid_cid(request.dispatch_request_cid) {
    return false
  }
  match request_identity(request) {
    Ok(identity) => identity == request.dispatch_request_cid
    Err(_) => false
  }
}

///|
fn emit_dispatch_request_body(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "budget_cid")
    @encode.string_value(writer, request.budget_cid)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, request.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, request.connector_revision)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, request.coordinator_authority)
    @encode.key(writer, "dispatch_id")
    @encode.string_value(writer, request.dispatch_id)
    @encode.key(writer, "evidence_issuer_capability_cid")
    @encode.string_value(writer, request.evidence_issuer_capability_cid)
    @encode.key(writer, "grant_cid")
    @encode.string_value(writer, request.grant_cid)
    @encode.key(writer, "input_binding_cid")
    @encode.string_value(writer, request.input_binding_cid)
    @encode.key(writer, "obligations_cid")
    @encode.string_value(writer, request.obligations_cid)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, request.run_definition_cid)
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, request.runtime_bundle_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, request.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, request.site_key)
    @encode.key(writer, "strategy_revision")
    @encode.string_value(writer, request.strategy_revision)
    @encode.key(writer, "task_attempt")
    @encode.number_value(writer, request.task_attempt.to_double())
    @encode.key(writer, "task_key")
    @encode.string_value(writer, request.task_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-request/0.2")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok(body)
}

///|
fn request_identity(request : DispatchRequest) -> Result[String, DispatchIssue] {
  let body = match emit_dispatch_request_body(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
fn emit_remote_dispatch_budget_body(
  budget : RemoteDispatchBudget,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(1024, 8, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "execution_bytes")
    @encode.string_value(writer, budget.execution_bytes.to_string())
    @encode.key(writer, "retained_bytes")
    @encode.string_value(writer, budget.retained_bytes.to_string())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-budget/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
fn remote_dispatch_budget_identity(
  budget : RemoteDispatchBudget,
) -> Result[String, DispatchIssue] {
  let body = match emit_remote_dispatch_budget_body(budget) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
pub fn prepare_remote_dispatch_budget(
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[RemoteDispatchBudget, DispatchIssue] {
  if retained_bytes < 0L || execution_bytes < 0L {
    return Err(InvalidDispatch)
  }
  let pending : RemoteDispatchBudget = {
    retained_bytes,
    execution_bytes,
    budget_cid: "pending",
  }
  let identity = match remote_dispatch_budget_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, budget_cid: identity, })
}

///|
pub fn admit_remote_dispatch_budget(
  retained_bytes : Int64,
  execution_bytes : Int64,
  claimed_budget_cid : String,
) -> Result[RemoteDispatchBudget, DispatchIssue] {
  let budget = match
    prepare_remote_dispatch_budget(retained_bytes, execution_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if budget.budget_cid != claimed_budget_cid {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(budget)
  }
}

///|
pub fn remote_dispatch_budget_cid(budget : RemoteDispatchBudget) -> String {
  budget.budget_cid
}

///|
pub fn remote_dispatch_budget_json(
  budget : RemoteDispatchBudget,
) -> Result[String, DispatchIssue] {
  if budget.retained_bytes < 0L ||
    budget.execution_bytes < 0L ||
    remote_dispatch_budget_identity(budget) != Ok(budget.budget_cid) {
    return Err(InvalidDispatch)
  }
  emit_remote_dispatch_budget_body(budget)
}

///|
pub fn remote_dispatch_budget_capacity(
  budget : RemoteDispatchBudget,
) -> (Int64, Int64) {
  (budget.retained_bytes, budget.execution_bytes)
}

///|
pub fn register_remote_evidence_issuer(
  site : @site.ExecutionSite,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  evidence_kind : String,
  issuer_capability_cid : String,
) -> Result[RemoteEvidenceIssuer, DispatchIssue] {
  if !@site.site_binding_current(
      site,
      @site.site_generation(site),
      runtime_bundle_cid,
    ) ||
    connector_registration.is_empty() ||
    connector_revision.is_empty() ||
    strategy_revision.is_empty() ||
    evidence_kind.is_empty() ||
    !valid_cid(issuer_capability_cid) {
    return Err(InvalidDispatch)
  }
  Ok({
    site_key: @site.site_key(site),
    site_generation: @site.site_generation(site),
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    evidence_kind,
    issuer_capability_cid,
  })
}

///|
pub fn register_remote_execution_capability(
  site : @site.ExecutionSite,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  operation_capability_cid : String,
) -> Result[RemoteExecutionCapability, DispatchIssue] {
  if !@site.site_binding_current(
      site,
      @site.site_generation(site),
      runtime_bundle_cid,
    ) ||
    connector_registration.is_empty() ||
    connector_revision.is_empty() ||
    strategy_revision.is_empty() ||
    !valid_cid(operation_capability_cid) {
    return Err(InvalidDispatch)
  }
  Ok({
    site_key: @site.site_key(site),
    site_generation: @site.site_generation(site),
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    operation_capability_cid,
  })
}

///|
pub fn remote_execution_capability_scope(
  capability : RemoteExecutionCapability,
) -> Array[String] {
  [
    capability.site_key,
    capability.site_generation.to_string(),
    capability.runtime_bundle_cid,
    capability.connector_registration,
    capability.connector_revision,
    capability.strategy_revision,
    capability.operation_capability_cid,
  ]
}

///|
/// Exact managed runtime registration selected before durable dispatch
/// admission. Execution permission and evidence issuance remain distinct, but
/// both must name the same installed implementation and Site generation.
pub fn remote_managed_runtime_registration_scope(
  capability : RemoteExecutionCapability,
  issuer : RemoteEvidenceIssuer,
) -> Result[Array[String], DispatchIssue] {
  if capability.site_key != issuer.site_key ||
    capability.site_generation != issuer.site_generation ||
    capability.runtime_bundle_cid != issuer.runtime_bundle_cid ||
    capability.connector_registration != issuer.connector_registration ||
    capability.connector_revision != issuer.connector_revision ||
    capability.strategy_revision != issuer.strategy_revision ||
    issuer.evidence_kind != remote_managed_output_evidence_kind() {
    return Err(InvalidDispatch)
  }
  Ok([
    capability.site_key,
    capability.site_generation.to_string(),
    capability.runtime_bundle_cid,
    capability.connector_registration,
    capability.connector_revision,
    capability.strategy_revision,
    capability.operation_capability_cid,
    issuer.issuer_capability_cid,
  ])
}

///|
pub fn remote_managed_output_evidence_kind() -> String {
  "actql.remote.managed-output/0.1"
}

///|
fn emit_remote_managed_output_measurement_body(
  measurement : RemoteManagedOutputMeasurement,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(262144, 65536, 3) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "admission_nodes")
    @encode.number_value(writer, measurement.admission_nodes.to_double())
    @encode.key(writer, "admission_text_bytes")
    @encode.number_value(writer, measurement.admission_text_bytes.to_double())
    @encode.key(writer, "admission_work")
    @encode.number_value(writer, measurement.admission_work.to_double())
    @encode.key(writer, "columns")
    @encode.begin_array(writer)
    for index in 0..<measurement.column_rows.length() {
      @encode.begin_object(writer)
      @encode.key(writer, "admitted_depth")
      @encode.number_value(
        writer,
        measurement.column_admitted_depths[index].to_double(),
      )
      @encode.key(writer, "bytes")
      @encode.number_value(writer, measurement.column_bytes[index].to_double())
      @encode.key(writer, "max_value_bytes")
      @encode.number_value(
        writer,
        measurement.column_max_value_bytes[index].to_double(),
      )
      @encode.key(writer, "nodes")
      @encode.number_value(writer, measurement.column_nodes[index].to_double())
      @encode.key(writer, "null_rows")
      @encode.number_value(
        writer,
        measurement.column_null_rows[index].to_double(),
      )
      @encode.key(writer, "rows")
      @encode.number_value(writer, measurement.column_rows[index].to_double())
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "row_count")
    @encode.number_value(writer, measurement.row_count.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-managed-output-measurement/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
fn valid_remote_managed_output_measurement_fields(
  measurement : RemoteManagedOutputMeasurement,
) -> Bool {
  let width = measurement.column_rows.length()
  if width > 4096 ||
    measurement.row_count < 0 ||
    measurement.admission_nodes < 0 ||
    measurement.admission_text_bytes < 0 ||
    measurement.admission_work < 0 ||
    measurement.column_bytes.length() != width ||
    measurement.column_nodes.length() != width ||
    measurement.column_max_value_bytes.length() != width ||
    measurement.column_null_rows.length() != width ||
    measurement.column_admitted_depths.length() != width {
    return false
  }
  for index in 0..<width {
    let rows = measurement.column_rows[index]
    let bytes = measurement.column_bytes[index]
    let nodes = measurement.column_nodes[index]
    let maximum = measurement.column_max_value_bytes[index]
    let nulls = measurement.column_null_rows[index]
    let depth = measurement.column_admitted_depths[index]
    if rows != measurement.row_count ||
      bytes < 0 ||
      nodes < 0 ||
      maximum < 0 ||
      maximum > bytes ||
      nulls < 0 ||
      nulls > rows ||
      depth < 0 ||
      (rows == 0 && (bytes != 0 || nodes != 0)) {
      return false
    }
  }
  true
}

///|
fn remote_managed_output_measurement_identity(
  measurement : RemoteManagedOutputMeasurement,
) -> Result[String, DispatchIssue] {
  let body = match emit_remote_managed_output_measurement_body(measurement) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
pub fn prepare_remote_managed_output_measurement(
  row_count : Int,
  admission_nodes : Int,
  admission_text_bytes : Int,
  admission_work : Int,
  column_rows : Array[Int],
  column_bytes : Array[Int],
  column_nodes : Array[Int],
  column_max_value_bytes : Array[Int],
  column_null_rows : Array[Int],
  column_admitted_depths : Array[Int],
) -> Result[RemoteManagedOutputMeasurement, DispatchIssue] {
  let pending : RemoteManagedOutputMeasurement = {
    row_count,
    admission_nodes,
    admission_text_bytes,
    admission_work,
    column_rows: column_rows.copy(),
    column_bytes: column_bytes.copy(),
    column_nodes: column_nodes.copy(),
    column_max_value_bytes: column_max_value_bytes.copy(),
    column_null_rows: column_null_rows.copy(),
    column_admitted_depths: column_admitted_depths.copy(),
    measurement_cid: "pending",
  }
  if !valid_remote_managed_output_measurement_fields(pending) {
    return Err(InvalidDispatch)
  }
  let identity = match remote_managed_output_measurement_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, measurement_cid: identity, })
}

///|
pub fn admit_remote_managed_output_measurement(
  row_count : Int,
  admission_nodes : Int,
  admission_text_bytes : Int,
  admission_work : Int,
  column_rows : Array[Int],
  column_bytes : Array[Int],
  column_nodes : Array[Int],
  column_max_value_bytes : Array[Int],
  column_null_rows : Array[Int],
  column_admitted_depths : Array[Int],
  claimed_measurement_cid : String,
) -> Result[RemoteManagedOutputMeasurement, DispatchIssue] {
  let measurement = match
    prepare_remote_managed_output_measurement(
      row_count, admission_nodes, admission_text_bytes, admission_work, column_rows,
      column_bytes, column_nodes, column_max_value_bytes, column_null_rows, column_admitted_depths,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if measurement.measurement_cid != claimed_measurement_cid {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(measurement)
  }
}

///|
pub fn remote_managed_output_measurement_cid(
  measurement : RemoteManagedOutputMeasurement,
) -> String {
  measurement.measurement_cid
}

///|
pub fn remote_managed_output_measurement_json(
  measurement : RemoteManagedOutputMeasurement,
) -> Result[String, DispatchIssue] {
  if !valid_remote_managed_output_measurement_fields(measurement) ||
    remote_managed_output_measurement_identity(measurement) !=
    Ok(measurement.measurement_cid) {
    return Err(InvalidDispatch)
  }
  emit_remote_managed_output_measurement_body(measurement)
}

///|
pub fn remote_managed_output_measurement_projection(
  measurement : RemoteManagedOutputMeasurement,
) -> Array[Array[Int]] {
  [
    [
      measurement.row_count,
      measurement.admission_nodes,
      measurement.admission_text_bytes,
      measurement.admission_work,
    ],
    measurement.column_rows.copy(),
    measurement.column_bytes.copy(),
    measurement.column_nodes.copy(),
    measurement.column_max_value_bytes.copy(),
    measurement.column_null_rows.copy(),
    measurement.column_admitted_depths.copy(),
  ]
}

///|
/// Derive the evidence identity for the common Site holding acquired for one
/// exact remote output. A physical executor reports the immutable material
/// generation and size, but cannot manufacture the holding authority that is
/// created later by the common runtime.
pub fn remote_output_holding_evidence_cid(
  request : DispatchRequest,
  material_generation : String,
  retained_bytes : Int64,
) -> Result[String, DispatchIssue] {
  if !valid_request(request) ||
    material_generation.is_empty() ||
    retained_bytes < 0L {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(32768, 16, 1) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "material_generation")
    @encode.string_value(writer, material_generation)
    @encode.key(writer, "retained_bytes")
    @encode.string_value(writer, retained_bytes.to_string())
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, request.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, request.site_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-output-holding/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
fn emit_remote_managed_output_subject_body(
  subject : RemoteManagedOutputSubject,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, subject.dispatch_request_cid)
    @encode.key(writer, "holding_evidence_cid")
    @encode.string_value(writer, subject.holding_evidence_cid)
    @encode.key(writer, "logical_view_cid")
    @encode.string_value(writer, subject.logical_view_cid)
    @encode.key(writer, "managed_profile_cid")
    @encode.string_value(writer, subject.managed_profile_cid)
    @encode.key(writer, "material_generation")
    @encode.string_value(writer, subject.material_generation)
    @encode.key(writer, "measurement_evidence_cid")
    @encode.string_value(writer, subject.measurement_evidence_cid)
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(writer, subject.physical_manifest_cid)
    @encode.key(writer, "representation_codec_cid")
    @encode.string_value(writer, subject.representation_codec_cid)
    @encode.key(writer, "result_schema_cid")
    @encode.string_value(writer, subject.result_schema_cid)
    @encode.key(writer, "retained_bytes")
    @encode.string_value(writer, subject.retained_bytes.to_string())
    @encode.key(writer, "row_count")
    @encode.number_value(writer, subject.row_count.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-managed-output-subject/0.2")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
fn remote_managed_output_subject_identity(
  subject : RemoteManagedOutputSubject,
) -> Result[String, DispatchIssue] {
  let body = match emit_remote_managed_output_subject_body(subject) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
fn valid_remote_managed_output_subject_fields(
  subject : RemoteManagedOutputSubject,
) -> Bool {
  valid_cid(subject.dispatch_request_cid) &&
  !subject.material_generation.is_empty() &&
  valid_cid(subject.holding_evidence_cid) &&
  valid_cid(subject.managed_profile_cid) &&
  valid_cid(subject.result_schema_cid) &&
  valid_cid(subject.logical_view_cid) &&
  valid_cid(subject.representation_codec_cid) &&
  valid_cid(subject.physical_manifest_cid) &&
  valid_cid(subject.measurement_evidence_cid) &&
  subject.row_count >= 0 &&
  subject.retained_bytes >= 0L
}

///|
pub fn prepare_remote_managed_output_subject(
  dispatch_request_cid : String,
  material_generation : String,
  holding_evidence_cid : String,
  managed_profile_cid : String,
  result_schema_cid : String,
  logical_view_cid : String,
  representation_codec_cid : String,
  physical_manifest_cid : String,
  measurement_evidence_cid : String,
  row_count : Int,
  retained_bytes : Int64,
) -> Result[RemoteManagedOutputSubject, DispatchIssue] {
  let pending : RemoteManagedOutputSubject = {
    dispatch_request_cid,
    material_generation,
    holding_evidence_cid,
    managed_profile_cid,
    result_schema_cid,
    logical_view_cid,
    representation_codec_cid,
    physical_manifest_cid,
    measurement_evidence_cid,
    row_count,
    retained_bytes,
    subject_cid: "pending",
  }
  if !valid_remote_managed_output_subject_fields(pending) {
    return Err(InvalidDispatch)
  }
  let identity = match remote_managed_output_subject_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, subject_cid: identity, })
}

///|
pub fn admit_remote_managed_output_subject(
  dispatch_request_cid : String,
  material_generation : String,
  holding_evidence_cid : String,
  managed_profile_cid : String,
  result_schema_cid : String,
  logical_view_cid : String,
  representation_codec_cid : String,
  physical_manifest_cid : String,
  measurement_evidence_cid : String,
  row_count : Int,
  retained_bytes : Int64,
  claimed_subject_cid : String,
) -> Result[RemoteManagedOutputSubject, DispatchIssue] {
  let subject = match
    prepare_remote_managed_output_subject(
      dispatch_request_cid, material_generation, holding_evidence_cid, managed_profile_cid,
      result_schema_cid, logical_view_cid, representation_codec_cid, physical_manifest_cid,
      measurement_evidence_cid, row_count, retained_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if subject.subject_cid != claimed_subject_cid {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(subject)
  }
}

///|
pub fn remote_managed_output_subject_json(
  subject : RemoteManagedOutputSubject,
) -> Result[String, DispatchIssue] {
  if !valid_remote_managed_output_subject_fields(subject) ||
    remote_managed_output_subject_identity(subject) != Ok(subject.subject_cid) {
    return Err(InvalidDispatch)
  }
  emit_remote_managed_output_subject_body(subject)
}

///|
pub fn remote_managed_output_subject_cid(
  subject : RemoteManagedOutputSubject,
) -> String {
  subject.subject_cid
}

///|
pub fn remote_managed_output_subject_projection(
  subject : RemoteManagedOutputSubject,
) -> Array[String] {
  [
    subject.dispatch_request_cid,
    subject.material_generation,
    subject.holding_evidence_cid,
    subject.managed_profile_cid,
    subject.result_schema_cid,
    subject.logical_view_cid,
    subject.representation_codec_cid,
    subject.physical_manifest_cid,
    subject.measurement_evidence_cid,
    subject.row_count.to_string(),
    subject.retained_bytes.to_string(),
    subject.subject_cid,
  ]
}

///|
/// Typed physical retention facts carried by the admitted output subject.
/// These facts identify a remote generation and its charged upper bound; they
/// are not a read capability, a logical CID or proof that the material is
/// currently available.
pub fn remote_managed_output_subject_retention(
  subject : RemoteManagedOutputSubject,
) -> (String, String, String, Int64) {
  (
    subject.material_generation,
    subject.holding_evidence_cid,
    subject.physical_manifest_cid,
    subject.retained_bytes,
  )
}

///|
pub fn remote_managed_output_subject_matches_dispatch(
  subject : RemoteManagedOutputSubject,
  request : DispatchRequest,
) -> Bool {
  if !valid_remote_managed_output_subject_fields(subject) ||
    subject.dispatch_request_cid != request.dispatch_request_cid ||
    remote_managed_output_subject_identity(subject) != Ok(subject.subject_cid) {
    return false
  }
  match
    remote_output_holding_evidence_cid(
      request,
      subject.material_generation,
      subject.retained_bytes,
    ) {
    Ok(expected) => subject.holding_evidence_cid == expected
    Err(_) => false
  }
}

///|
pub fn remote_managed_output_subject_matches_measurement(
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Bool {
  valid_remote_managed_output_subject_fields(subject) &&
  valid_remote_managed_output_measurement_fields(measurement) &&
  remote_managed_output_subject_identity(subject) == Ok(subject.subject_cid) &&
  remote_managed_output_measurement_identity(measurement) ==
  Ok(measurement.measurement_cid) &&
  subject.measurement_evidence_cid == measurement.measurement_cid &&
  subject.row_count == measurement.row_count
}

///|
fn emit_remote_execution_evidence_body(
  evidence : RemoteExecutionEvidence,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, evidence.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, evidence.connector_revision)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, evidence.dispatch_request_cid)
    @encode.key(writer, "evidence_kind")
    @encode.string_value(writer, evidence.evidence_kind)
    @encode.key(writer, "evidence_subject_cid")
    @encode.string_value(writer, evidence.evidence_subject_cid)
    @encode.key(writer, "holding_evidence_cid")
    @encode.string_value(writer, evidence.holding_evidence_cid)
    @encode.key(writer, "issuer_capability_cid")
    @encode.string_value(writer, evidence.issuer_capability_cid)
    @encode.key(writer, "material_generation")
    @encode.string_value(writer, evidence.material_generation)
    @encode.key(writer, "obligations_cid")
    @encode.string_value(writer, evidence.obligations_cid)
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, evidence.runtime_bundle_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, evidence.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, evidence.site_key)
    @encode.key(writer, "strategy_revision")
    @encode.string_value(writer, evidence.strategy_revision)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-execution-evidence/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
fn remote_execution_evidence_identity(
  evidence : RemoteExecutionEvidence,
) -> Result[String, DispatchIssue] {
  let body = match emit_remote_execution_evidence_body(evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
fn valid_remote_execution_evidence_fields(
  evidence : RemoteExecutionEvidence,
) -> Bool {
  valid_cid(evidence.dispatch_request_cid) &&
  !evidence.site_key.is_empty() &&
  evidence.site_generation >= 0 &&
  valid_cid(evidence.runtime_bundle_cid) &&
  !evidence.connector_registration.is_empty() &&
  !evidence.connector_revision.is_empty() &&
  !evidence.strategy_revision.is_empty() &&
  valid_cid(evidence.obligations_cid) &&
  !evidence.material_generation.is_empty() &&
  valid_cid(evidence.holding_evidence_cid) &&
  !evidence.evidence_kind.is_empty() &&
  valid_cid(evidence.evidence_subject_cid) &&
  valid_cid(evidence.issuer_capability_cid)
}

///|
pub fn admit_remote_execution_evidence(
  connector_registration : String,
  connector_revision : String,
  dispatch_request_cid : String,
  evidence_kind : String,
  evidence_subject_cid : String,
  holding_evidence_cid : String,
  issuer_capability_cid : String,
  material_generation : String,
  obligations_cid : String,
  runtime_bundle_cid : String,
  site_generation : Int,
  site_key : String,
  strategy_revision : String,
  claimed_evidence_cid : String,
) -> Result[RemoteExecutionEvidence, DispatchIssue] {
  let evidence : RemoteExecutionEvidence = {
    connector_registration,
    connector_revision,
    dispatch_request_cid,
    evidence_kind,
    evidence_subject_cid,
    holding_evidence_cid,
    issuer_capability_cid,
    material_generation,
    obligations_cid,
    runtime_bundle_cid,
    site_generation,
    site_key,
    strategy_revision,
    evidence_cid: claimed_evidence_cid,
  }
  if !valid_remote_execution_evidence_fields(evidence) ||
    remote_execution_evidence_identity(evidence) != Ok(claimed_evidence_cid) {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(evidence)
  }
}

///|
pub fn remote_execution_evidence_matches_dispatch(
  evidence : RemoteExecutionEvidence,
  request : DispatchRequest,
) -> Bool {
  valid_remote_execution_evidence_fields(evidence) &&
  evidence.dispatch_request_cid == request.dispatch_request_cid &&
  evidence.site_key == request.site_key &&
  evidence.site_generation == request.site_generation &&
  evidence.runtime_bundle_cid == request.runtime_bundle_cid &&
  evidence.connector_registration == request.connector_registration &&
  evidence.connector_revision == request.connector_revision &&
  evidence.strategy_revision == request.strategy_revision &&
  evidence.obligations_cid == request.obligations_cid &&
  evidence.issuer_capability_cid == request.evidence_issuer_capability_cid &&
  remote_execution_evidence_identity(evidence) == Ok(evidence.evidence_cid)
}

///|
pub fn issue_remote_execution_evidence(
  issuer : RemoteEvidenceIssuer,
  record : DispatchRecord,
  evidence_subject_cid : String,
) -> Result[RemoteExecutionEvidence, DispatchIssue] {
  let request = record.request
  if !valid_cid(evidence_subject_cid) ||
    request.site_key != issuer.site_key ||
    request.site_generation != issuer.site_generation ||
    request.runtime_bundle_cid != issuer.runtime_bundle_cid ||
    request.connector_registration != issuer.connector_registration ||
    request.connector_revision != issuer.connector_revision ||
    request.strategy_revision != issuer.strategy_revision ||
    request.evidence_issuer_capability_cid != issuer.issuer_capability_cid ||
    record.execution != NativeSettled ||
    !record.material_available {
    return Err(InvalidDispatch)
  }
  let (material_generation, holding_evidence_cid) = match record.evidence {
    OutputRetained(material, holding) => (material, holding)
    _ => return Err(InvalidTransition)
  }
  let pending : RemoteExecutionEvidence = {
    dispatch_request_cid: request.dispatch_request_cid,
    site_key: request.site_key,
    site_generation: request.site_generation,
    runtime_bundle_cid: request.runtime_bundle_cid,
    connector_registration: request.connector_registration,
    connector_revision: request.connector_revision,
    strategy_revision: request.strategy_revision,
    obligations_cid: request.obligations_cid,
    material_generation,
    holding_evidence_cid,
    evidence_kind: issuer.evidence_kind,
    evidence_subject_cid,
    issuer_capability_cid: issuer.issuer_capability_cid,
    evidence_cid: "pending",
  }
  let identity = match remote_execution_evidence_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, evidence_cid: identity, })
}

///|
pub fn issue_remote_managed_output_evidence(
  issuer : RemoteEvidenceIssuer,
  record : DispatchRecord,
  subject : RemoteManagedOutputSubject,
) -> Result[RemoteExecutionEvidence, DispatchIssue] {
  let request = record.request
  let (material_generation, holding_evidence_cid) = match record.evidence {
    OutputRetained(material, holding) => (material, holding)
    _ => return Err(InvalidTransition)
  }
  if issuer.evidence_kind != remote_managed_output_evidence_kind() ||
    !remote_managed_output_subject_matches_dispatch(subject, request) ||
    subject.material_generation != material_generation ||
    subject.holding_evidence_cid != holding_evidence_cid {
    return Err(InvalidDispatch)
  }
  issue_remote_execution_evidence(issuer, record, subject.subject_cid)
}

///|
pub fn remote_managed_output_subject_matches_evidence(
  subject : RemoteManagedOutputSubject,
  evidence : RemoteExecutionEvidence,
  request : DispatchRequest,
) -> Bool {
  evidence.evidence_kind == remote_managed_output_evidence_kind() &&
  remote_execution_evidence_matches_dispatch(evidence, request) &&
  remote_managed_output_subject_matches_dispatch(subject, request) &&
  evidence.evidence_subject_cid == subject.subject_cid &&
  evidence.material_generation == subject.material_generation &&
  evidence.holding_evidence_cid == subject.holding_evidence_cid
}

///|
pub fn remote_execution_evidence_json(
  evidence : RemoteExecutionEvidence,
) -> Result[String, DispatchIssue] {
  if !valid_remote_execution_evidence_fields(evidence) {
    return Err(InvalidDispatch)
  }
  let identity = match remote_execution_evidence_identity(evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != evidence.evidence_cid {
    return Err(InvalidDispatch)
  }
  emit_remote_execution_evidence_body(evidence)
}

///|
pub fn remote_execution_evidence_cid(
  evidence : RemoteExecutionEvidence,
) -> String {
  evidence.evidence_cid
}

///|
pub fn dispatch_request_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  emit_dispatch_request_body(request)
}

///|
/// Exact implementation scope used only to select a Host-installed runtime.
/// It contains no future output or transport-session identity.
pub fn dispatch_request_execution_scope(
  request : DispatchRequest,
) -> Array[String] {
  [
    request.site_key,
    request.site_generation.to_string(),
    request.runtime_bundle_cid,
    request.connector_registration,
    request.connector_revision,
    request.strategy_revision,
    request.grant_cid,
    request.evidence_issuer_capability_cid,
  ]
}

///|
pub fn dispatch_request_budget_cid(request : DispatchRequest) -> String {
  request.budget_cid
}

///|
/// Selected Host registration named by this exact dispatch. The registration
/// name is only one part of execution admission; it grants no capability by
/// itself.
pub fn dispatch_request_connector_registration(
  request : DispatchRequest,
) -> String {
  request.connector_registration
}

///|
/// Exact checked task selected by this dispatch. The pair identifies the
/// preinstalled executable task definition, not a future execution result or
/// a transport occurrence.
pub fn dispatch_request_task_scope(
  request : DispatchRequest,
) -> (String, String) {
  (request.run_definition_cid, request.task_key)
}

///|
pub fn dispatch_record_matches_request(
  record : DispatchRecord,
  request : DispatchRequest,
) -> Bool {
  record.request.dispatch_request_cid == request.dispatch_request_cid
}

///|
pub fn prepare_dispatch_request(
  coordinator_authority : String,
  run_definition_cid : String,
  task_key : String,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  input_binding_cid : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
) -> Result[DispatchRequest, DispatchIssue] {
  let pending : DispatchRequest = {
    coordinator_authority,
    run_definition_cid,
    task_key,
    task_attempt,
    dispatch_id,
    dispatch_request_cid: "pending",
    site_key,
    site_generation,
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    input_binding_cid,
    obligations_cid,
    budget_cid,
    evidence_issuer_capability_cid,
    grant_cid,
  }
  if !valid_request_fields(pending) {
    return Err(InvalidDispatch)
  }
  let identity = match request_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, dispatch_request_cid: identity, })
}

///|
/// Admit decoded transport fields by recomputing their application identity.
pub fn admit_dispatch_request(
  coordinator_authority : String,
  run_definition_cid : String,
  task_key : String,
  task_attempt : Int,
  dispatch_id : String,
  claimed_request_cid : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  input_binding_cid : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
) -> Result[DispatchRequest, DispatchIssue] {
  let request = match
    prepare_dispatch_request(
      coordinator_authority, run_definition_cid, task_key, task_attempt, dispatch_id,
      site_key, site_generation, runtime_bundle_cid, connector_registration, connector_revision,
      strategy_revision, input_binding_cid, obligations_cid, budget_cid, evidence_issuer_capability_cid,
      grant_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if request.dispatch_request_cid != claimed_request_cid {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(request)
  }
}

///|
pub fn create_site_dispatch_journal(
  site : @site.ExecutionSite,
  protocol_version : String,
) -> Result[SiteDispatchJournal, DispatchIssue] {
  if !valid_cid(@site.site_runtime_revision(site)) ||
    protocol_version != "actql-remote-site/0.1" {
    return Err(InvalidJournal)
  }
  Ok({ site, protocol_version, dispatches: Map([]), attempts: Map([]), })
}

///|
/// Prepare an exact admission without mutating the in-memory journal. The
/// returned request body is the durable CAS input for a journal adapter.
pub fn prepare_dispatch_acceptance(
  journal : SiteDispatchJournal,
  request : DispatchRequest,
) -> Result[DispatchAdmission, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  if request.site_key != @site.site_key(journal.site) {
    return Err(ForeignSite)
  }
  if !@site.site_binding_current(
      journal.site,
      request.site_generation,
      request.runtime_bundle_cid,
    ) {
    return Err(StaleSiteGeneration)
  }
  let key = dispatch_key(request)
  match journal.dispatches.get(key) {
    Some(record) =>
      if record.request.dispatch_request_cid == request.dispatch_request_cid {
        Ok({ journal, request, acceptance: ExistingDispatch, consumed: false, })
      } else {
        Err(DispatchCollision)
      }
    None => {
      let occurrence = attempt_key(request)
      if journal.attempts.contains(occurrence) {
        return Err(AttemptAlreadyDispatched)
      }
      Ok({ journal, request, acceptance: NewDispatch, consumed: false, })
    }
  }
}

///|
/// Commit admission only after the adapter confirms the accepted request is
/// durable. The recheck prevents two prepared admissions from creating two
/// physical executions for one task attempt.
pub fn commit_dispatch_acceptance(
  admission : DispatchAdmission,
  durable : Bool,
) -> Result[(DispatchAcceptance, DispatchRecord), DispatchIssue] {
  if admission.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  let journal = admission.journal
  let request = admission.request
  let key = dispatch_key(request)
  match journal.dispatches.get(key) {
    Some(record) => {
      if record.request.dispatch_request_cid != request.dispatch_request_cid {
        return Err(DispatchCollision)
      }
      admission.consumed = true
      Ok((ExistingDispatch, record))
    }
    None => {
      if admission.acceptance == ExistingDispatch {
        return Err(InvalidTransition)
      }
      let occurrence = attempt_key(request)
      if journal.attempts.contains(occurrence) {
        return Err(AttemptAlreadyDispatched)
      }
      let record = {
        request,
        revision: 0,
        execution: Accepted,
        evidence: NoEvidence,
        cleanup: CleanupActive,
        material_available: false,
        quarantined_capacity: false,
      }
      journal.dispatches[key] = record
      journal.attempts[occurrence] = key
      admission.consumed = true
      Ok((NewDispatch, record))
    }
  }
}

///|
/// Reinstall an exact durable historical request after process restart. This
/// does not authorize execution and accepts only this Site's prior generation.
pub fn restore_historical_dispatch(
  journal : SiteDispatchJournal,
  request : DispatchRequest,
) -> Result[DispatchRecord, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  if request.site_key != @site.site_key(journal.site) {
    return Err(ForeignSite)
  }
  if request.site_generation > @site.site_generation(journal.site) {
    return Err(StaleSiteGeneration)
  }
  let key = dispatch_key(request)
  match journal.dispatches.get(key) {
    Some(record) =>
      if record.request.dispatch_request_cid == request.dispatch_request_cid {
        Ok(record)
      } else {
        Err(DispatchCollision)
      }
    None => {
      let occurrence = attempt_key(request)
      if journal.attempts.contains(occurrence) {
        return Err(AttemptAlreadyDispatched)
      }
      let record = {
        request,
        revision: 0,
        execution: Accepted,
        evidence: NoEvidence,
        cleanup: CleanupActive,
        material_available: false,
        quarantined_capacity: false,
      }
      journal.dispatches[key] = record
      journal.attempts[occurrence] = key
      Ok(record)
    }
  }
}

///|
pub fn dispatch_admission_kind(
  admission : DispatchAdmission,
) -> DispatchAcceptance {
  admission.acceptance
}

///|
pub fn dispatch_admission_request_json(
  admission : DispatchAdmission,
) -> Result[String, DispatchIssue] {
  dispatch_request_json(admission.request)
}

///|
fn prepare_transition(
  record : DispatchRecord,
  next_execution : RemoteExecutionState,
  next_evidence : RemoteEvidenceState,
  next_cleanup : RemoteCleanupState,
  next_material_available : Bool,
  next_quarantined_capacity : Bool,
) -> DispatchTransition {
  {
    record,
    expected_revision: record.revision,
    expected_execution: record.execution,
    expected_evidence: record.evidence,
    expected_cleanup: record.cleanup,
    expected_material_available: record.material_available,
    expected_quarantined_capacity: record.quarantined_capacity,
    next_execution,
    next_evidence,
    next_cleanup,
    next_material_available,
    next_quarantined_capacity,
    consumed: false,
  }
}

///|
pub fn prepare_begin_provisioning(
  record : DispatchRecord,
  capability : RemoteExecutionCapability,
) -> Result[DispatchTransition, DispatchIssue] {
  let request = record.request
  if request.site_key != capability.site_key ||
    request.site_generation != capability.site_generation ||
    request.runtime_bundle_cid != capability.runtime_bundle_cid ||
    request.connector_registration != capability.connector_registration ||
    request.connector_revision != capability.connector_revision ||
    request.strategy_revision != capability.strategy_revision ||
    request.grant_cid != capability.operation_capability_cid {
    return Err(InvalidDispatch)
  }
  match record.execution {
    Accepted =>
      Ok(
        prepare_transition(
          record,
          Provisioning,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
/// Managed execution cannot begin under an execution capability paired with a
/// different evidence issuer. Candidate support uses the same scope before
/// durable admission; this check protects the transition independently.
pub fn prepare_begin_managed_provisioning(
  record : DispatchRecord,
  capability : RemoteExecutionCapability,
  issuer : RemoteEvidenceIssuer,
) -> Result[DispatchTransition, DispatchIssue] {
  let request = record.request
  let expected = dispatch_request_execution_scope(request)
  let registered = match
    remote_managed_runtime_registration_scope(capability, issuer) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if expected != registered {
    return Err(InvalidDispatch)
  }
  prepare_begin_provisioning(record, capability)
}

///|
pub fn prepare_begin_remote_execution(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.execution {
    Provisioning =>
      Ok(
        prepare_transition(
          record,
          Running,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_confirm_native_settled(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.execution {
    Running =>
      Ok(
        prepare_transition(
          record,
          NativeSettled,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn commit_dispatch_transition(
  transition : DispatchTransition,
  durable : Bool,
) -> Result[Unit, DispatchIssue] {
  if transition.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  if !transition_matches_current(transition) {
    return Err(StateCollision)
  }
  apply_transition(transition)
  Ok(())
}

///|
fn transition_matches_current(transition : DispatchTransition) -> Bool {
  let record = transition.record
  record.revision == transition.expected_revision &&
  record.execution == transition.expected_execution &&
  record.evidence == transition.expected_evidence &&
  record.cleanup == transition.expected_cleanup &&
  record.material_available == transition.expected_material_available &&
  record.quarantined_capacity == transition.expected_quarantined_capacity
}

///|
fn apply_transition(transition : DispatchTransition) -> Unit {
  let record = transition.record
  record.execution = transition.next_execution
  record.evidence = transition.next_evidence
  record.cleanup = transition.next_cleanup
  record.material_available = transition.next_material_available
  record.quarantined_capacity = transition.next_quarantined_capacity
  record.revision += 1
  transition.consumed = true
}

///|
fn transition_has_state_collision(transition : DispatchTransition) -> Bool {
  transition.consumed || !transition_matches_current(transition)
}

///|
pub fn prepare_confirm_execution_failed(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.execution {
    Provisioning | Running =>
      Ok(
        prepare_transition(
          record,
          ExecutionFailed,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_confirm_execution_cancelled(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.execution {
    Accepted | Provisioning | Running =>
      Ok(
        prepare_transition(
          record,
          ExecutionCancelled,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
/// A rejected operation may become terminal only after its cleanup authority
/// confirms that the previously unknown physical execution has stopped.
pub fn prepare_reconcile_failed_execution(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match (record.execution, record.cleanup) {
    (ExecutionUnknown, CleanupUnknown) =>
      Ok(
        prepare_transition(
          record,
          ExecutionFailed,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_reconcile_cancelled_execution(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match (record.execution, record.cleanup) {
    (ExecutionUnknown, CleanupUnknown) =>
      Ok(
        prepare_transition(
          record,
          ExecutionCancelled,
          record.evidence,
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_retain_remote_output(
  record : DispatchRecord,
  material_generation : String,
  holding_evidence_cid : String,
) -> Result[DispatchTransition, DispatchIssue] {
  if material_generation.is_empty() || !valid_cid(holding_evidence_cid) {
    return Err(InvalidDispatch)
  }
  match (record.execution, record.evidence, record.cleanup) {
    (NativeSettled, NoEvidence, CleanupActive) =>
      Ok(
        prepare_transition(
          record,
          record.execution,
          OutputRetained(material_generation, holding_evidence_cid),
          record.cleanup,
          true,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_durable_execution_evidence(
  record : DispatchRecord,
  evidence : RemoteExecutionEvidence,
) -> Result[DispatchTransition, DispatchIssue] {
  let request = record.request
  if !remote_execution_evidence_matches_dispatch(evidence, request) {
    return Err(InvalidDispatch)
  }
  match record.evidence {
    OutputRetained(material_generation, holding_evidence_cid) => {
      if !record.material_available ||
        evidence.material_generation != material_generation ||
        evidence.holding_evidence_cid != holding_evidence_cid {
        return Err(MaterialUnavailable)
      }
      Ok(
        prepare_transition(
          record,
          record.execution,
          EvidenceDurable(
            material_generation,
            holding_evidence_cid,
            evidence.evidence_cid,
          ),
          record.cleanup,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_reject_execution_evidence(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.evidence {
    NoEvidence | OutputRetained(_, _) =>
      Ok(
        prepare_transition(
          record,
          record.execution,
          EvidenceRejected,
          record.cleanup,
          false,
          record.quarantined_capacity,
        ),
      )
    EvidenceDurable(_, _, _) => Err(InvalidTransition)
    EvidenceRejected => Err(InvalidTransition)
  }
}

///|
pub fn prepare_mark_execution_unknown(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  let execution = match record.execution {
    Accepted | Provisioning | Running => ExecutionUnknown
    state => state
  }
  let cleanup = match record.cleanup {
    CleanupReleased | CleanupRecoveredAfterLoss => record.cleanup
    _ => CleanupUnknown
  }
  if execution == record.execution && cleanup == record.cleanup {
    return Err(InvalidTransition)
  }
  Ok(
    prepare_transition(
      record,
      execution,
      record.evidence,
      cleanup,
      record.material_available,
      record.quarantined_capacity,
    ),
  )
}

///|
pub fn prepare_begin_remote_release(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.cleanup {
    CleanupActive | CleanupUnknown =>
      Ok(
        prepare_transition(
          record,
          record.execution,
          record.evidence,
          CleanupReleasing,
          record.material_available,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
pub fn prepare_confirm_remote_release(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.cleanup {
    CleanupReleasing =>
      Ok(
        prepare_transition(
          record,
          record.execution,
          record.evidence,
          CleanupReleased,
          false,
          record.quarantined_capacity,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
/// Force loss terminates management without claiming physical reclamation.
pub fn prepare_force_loss(
  journal : SiteDispatchJournal,
  record : DispatchRecord,
  authorized : Bool,
) -> Result[ForceLossTransition, DispatchIssue] {
  if !authorized {
    return Err(UnauthorizedForceLoss)
  }
  if record.request.site_key != @site.site_key(journal.site) {
    return Err(ForeignSite)
  }
  Ok({
    journal,
    transition: prepare_transition(
      record,
      ExecutionUnknown,
      record.evidence,
      CleanupForceLost,
      false,
      true,
    ),
  })
}

///|
pub fn commit_force_loss(
  force : ForceLossTransition,
  durable : Bool,
) -> Result[Unit, DispatchIssue] {
  match commit_dispatch_transition(force.transition, durable) {
    Ok(_) => {
      @site.revoke_site(force.journal.site)
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Late exact cleanup evidence may discharge quarantined physical capacity. It
/// never restores execution success, material availability, or completion.
pub fn prepare_reconcile_cleanup_after_loss(
  record : DispatchRecord,
) -> Result[DispatchTransition, DispatchIssue] {
  match record.cleanup {
    CleanupForceLost =>
      Ok(
        prepare_transition(
          record,
          record.execution,
          record.evidence,
          CleanupRecoveredAfterLoss,
          record.material_available,
          false,
        ),
      )
    _ => Err(InvalidTransition)
  }
}

///|
/// Starting a new Agent generation invalidates old execution authority. Old
/// terminal facts remain queryable, while current material availability must
/// be established again through a separate physical check.
pub fn prepare_site_generation_restart(
  journal : SiteDispatchJournal,
  replacement : @site.ExecutionSite,
) -> Result[SiteRestartTransition, DispatchIssue] {
  if @site.site_key(replacement) != @site.site_key(journal.site) ||
    @site.site_generation(replacement) <= @site.site_generation(journal.site) ||
    !valid_cid(@site.site_runtime_revision(replacement)) {
    return Err(InvalidJournal)
  }
  if @site.site_revoked(journal.site) {
    return Err(QuarantinedCapacity)
  }
  let transitions : Array[DispatchTransition] = []
  let mut quarantined = false
  journal.dispatches.each((_, record) => {
    if record.quarantined_capacity || record.cleanup == CleanupForceLost {
      quarantined = true
    }
    if record.cleanup != CleanupReleased &&
      record.cleanup != CleanupRecoveredAfterLoss {
      let execution = match record.execution {
        Accepted | Provisioning | Running => ExecutionUnknown
        state => state
      }
      if execution != record.execution ||
        record.cleanup != CleanupUnknown ||
        record.material_available {
        transitions.push(
          prepare_transition(
            record,
            execution,
            record.evidence,
            CleanupUnknown,
            false,
            record.quarantined_capacity,
          ),
        )
      }
    }
  })
  if quarantined {
    return Err(QuarantinedCapacity)
  }
  Ok({
    journal,
    replacement,
    expected_generation: @site.site_generation(journal.site),
    transitions,
    consumed: false,
  })
}

///|
pub fn commit_site_generation_restart(
  restart : SiteRestartTransition,
  durable : Bool,
) -> Result[Int, DispatchIssue] {
  if restart.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  if @site.site_generation(restart.journal.site) != restart.expected_generation {
    return Err(StateCollision)
  }
  let mut collision = false
  restart.transitions.each(transition => {
    if transition_has_state_collision(transition) {
      collision = true
    }
  })
  if collision {
    return Err(StateCollision)
  }
  restart.transitions.each(apply_transition)
  restart.journal.site = restart.replacement
  restart.consumed = true
  Ok(restart.transitions.length())
}

///|
pub fn stop_site_admission(journal : SiteDispatchJournal) -> Unit {
  @site.begin_site_teardown(journal.site)
}

///|
pub fn remote_completion_evidence_available(record : DispatchRecord) -> Bool {
  record.execution == NativeSettled &&
  record.material_available &&
  record.evidence is EvidenceDurable(_, _, _) &&
  record.cleanup != CleanupForceLost &&
  record.cleanup != CleanupRecoveredAfterLoss &&
  record.cleanup != CleanupReleased
}

///|
/// Historical completion and current material availability stay distinct.
/// This predicate reports only that the exact Site cleanup responsibility was
/// durably released; it grants no new execution or read authority.
pub fn remote_runtime_record_released(record : DispatchRecord) -> Bool {
  record.cleanup == CleanupReleased && !record.material_available
}

///|
pub fn dispatch_record_state(
  record : DispatchRecord,
) -> (RemoteExecutionState, RemoteEvidenceState, RemoteCleanupState, Bool, Bool) {
  (
    record.execution,
    record.evidence,
    record.cleanup,
    record.material_available,
    record.quarantined_capacity,
  )
}

///|
fn execution_state_code(state : RemoteExecutionState) -> Int {
  match state {
    Accepted => 0
    Provisioning => 1
    Running => 2
    NativeSettled => 3
    ExecutionFailed => 4
    ExecutionCancelled => 5
    ExecutionUnknown => 6
  }
}

///|
fn evidence_state_code(state : RemoteEvidenceState) -> Int {
  match state {
    NoEvidence => 0
    OutputRetained(_, _) => 1
    EvidenceDurable(_, _, _) => 2
    EvidenceRejected => 3
  }
}

///|
fn cleanup_state_code(state : RemoteCleanupState) -> Int {
  match state {
    CleanupActive => 0
    CleanupReleasing => 1
    CleanupReleased => 2
    CleanupUnknown => 3
    CleanupForceLost => 4
    CleanupRecoveredAfterLoss => 5
  }
}

///|
fn evidence_state_fields(state : RemoteEvidenceState) -> Array[String] {
  match state {
    NoEvidence | EvidenceRejected => ["", "", ""]
    OutputRetained(material, holding) => [material, holding, ""]
    EvidenceDurable(material, holding, evidence) =>
      [material, holding, evidence]
  }
}

///|
fn bool_code(value : Bool) -> String {
  if value {
    "1"
  } else {
    "0"
  }
}

///|
fn execution_state_from_code(
  code : Int,
) -> Result[RemoteExecutionState, DispatchIssue] {
  match code {
    0 => Ok(Accepted)
    1 => Ok(Provisioning)
    2 => Ok(Running)
    3 => Ok(NativeSettled)
    4 => Ok(ExecutionFailed)
    5 => Ok(ExecutionCancelled)
    6 => Ok(ExecutionUnknown)
    _ => Err(InvalidJournal)
  }
}

///|
fn evidence_state_from_fields(
  code : Int,
  material : String,
  holding : String,
  evidence : String,
) -> Result[RemoteEvidenceState, DispatchIssue] {
  match code {
    0 if material.is_empty() && holding.is_empty() && evidence.is_empty() =>
      Ok(NoEvidence)
    1 if !material.is_empty() && valid_cid(holding) && evidence.is_empty() =>
      Ok(OutputRetained(material, holding))
    2 if !material.is_empty() && valid_cid(holding) && valid_cid(evidence) =>
      Ok(EvidenceDurable(material, holding, evidence))
    3 if material.is_empty() && holding.is_empty() && evidence.is_empty() =>
      Ok(EvidenceRejected)
    _ => Err(InvalidJournal)
  }
}

///|
fn cleanup_state_from_code(
  code : Int,
) -> Result[RemoteCleanupState, DispatchIssue] {
  match code {
    0 => Ok(CleanupActive)
    1 => Ok(CleanupReleasing)
    2 => Ok(CleanupReleased)
    3 => Ok(CleanupUnknown)
    4 => Ok(CleanupForceLost)
    5 => Ok(CleanupRecoveredAfterLoss)
    _ => Err(InvalidJournal)
  }
}

///|
/// Stable adapter projection. Codes are local API values, not wire identity.
pub fn dispatch_record_state_codes(record : DispatchRecord) -> Array[Int] {
  [
    execution_state_code(record.execution),
    evidence_state_code(record.evidence),
    cleanup_state_code(record.cleanup),
    if record.material_available {
      1
    } else {
      0
    },
    if record.quarantined_capacity {
      1
    } else {
      0
    },
  ]
}

///|
pub fn dispatch_record_revision(record : DispatchRecord) -> Int {
  record.revision
}

///|
/// Restore a durable state into a freshly accepted in-memory record. This is
/// reconciliation, not permission to advance or revive physical authority.
pub fn restore_dispatch_record(
  record : DispatchRecord,
  revision : Int,
  execution_code : Int,
  evidence_code : Int,
  cleanup_code : Int,
  material_available : Bool,
  quarantined_capacity : Bool,
  material_generation : String,
  holding_evidence_cid : String,
  execution_evidence_cid : String,
) -> Result[Unit, DispatchIssue] {
  if record.revision != 0 ||
    record.execution != Accepted ||
    record.evidence != NoEvidence ||
    record.cleanup != CleanupActive ||
    record.material_available ||
    record.quarantined_capacity ||
    revision < 0 {
    return Err(InvalidTransition)
  }
  let execution = match execution_state_from_code(execution_code) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let evidence = match
    evidence_state_from_fields(
      evidence_code, material_generation, holding_evidence_cid, execution_evidence_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cleanup = match cleanup_state_from_code(cleanup_code) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if (
      material_available &&
      !(evidence is OutputRetained(_, _) || evidence is EvidenceDurable(_, _, _))
    ) ||
    (quarantined_capacity && cleanup != CleanupForceLost) ||
    (cleanup == CleanupRecoveredAfterLoss && quarantined_capacity) ||
    (
      revision == 0 &&
      (
        execution != Accepted ||
        evidence != NoEvidence ||
        cleanup != CleanupActive ||
        material_available ||
        quarantined_capacity
      )
    ) {
    return Err(InvalidJournal)
  }
  record.revision = revision
  record.execution = execution
  record.evidence = evidence
  record.cleanup = cleanup
  record.material_available = material_available
  record.quarantined_capacity = quarantined_capacity
  Ok(())
}

///|
/// Exact CAS projection for a durable physical journal. State codes are not a
/// transport contract and remain subordinate to the MoonBit transition.
pub fn dispatch_transition_projection(
  transition : DispatchTransition,
) -> Array[String] {
  let expected_evidence = evidence_state_fields(transition.expected_evidence)
  let next_evidence = evidence_state_fields(transition.next_evidence)
  [
    transition.expected_revision.to_string(),
    execution_state_code(transition.expected_execution).to_string(),
    evidence_state_code(transition.expected_evidence).to_string(),
    cleanup_state_code(transition.expected_cleanup).to_string(),
    bool_code(transition.expected_material_available),
    bool_code(transition.expected_quarantined_capacity),
    expected_evidence[0],
    expected_evidence[1],
    expected_evidence[2],
    (transition.expected_revision + 1).to_string(),
    execution_state_code(transition.next_execution).to_string(),
    evidence_state_code(transition.next_evidence).to_string(),
    cleanup_state_code(transition.next_cleanup).to_string(),
    bool_code(transition.next_material_available),
    bool_code(transition.next_quarantined_capacity),
    next_evidence[0],
    next_evidence[1],
    next_evidence[2],
  ]
}

///|
/// Whether this transition exercises execution authority for the current Site
/// generation. Cleanup-only transitions remain available for historical
/// generations so a restart cannot strand physical responsibility.
pub fn dispatch_transition_requires_current_site(
  transition : DispatchTransition,
) -> Bool {
  transition.expected_execution != transition.next_execution ||
  transition.expected_evidence != transition.next_evidence
}

///|
pub fn dispatch_transition_journal_key(
  transition : DispatchTransition,
) -> Array[String] {
  dispatch_request_journal_key(transition.record.request)
}

///|
pub fn force_loss_projection(force : ForceLossTransition) -> Array[String] {
  dispatch_transition_projection(force.transition)
}

///|
pub fn force_loss_journal_key(force : ForceLossTransition) -> Array[String] {
  dispatch_transition_journal_key(force.transition)
}

///|
pub fn site_restart_transition_count(restart : SiteRestartTransition) -> Int {
  restart.transitions.length()
}

///|
pub fn site_restart_transition_at(
  restart : SiteRestartTransition,
  index : Int,
) -> DispatchTransition? {
  restart.transitions.get(index)
}

///|
pub fn site_restart_metadata(restart : SiteRestartTransition) -> Array[String] {
  [
    @site.site_key(restart.journal.site),
    restart.expected_generation.to_string(),
    @site.site_generation(restart.replacement).to_string(),
    @site.site_runtime_revision(restart.replacement),
  ]
}

///|
pub fn site_dispatch_generation(journal : SiteDispatchJournal) -> Int {
  @site.site_generation(journal.site)
}

///|
pub fn site_dispatch_protocol_version(journal : SiteDispatchJournal) -> String {
  journal.protocol_version
}

///|
pub fn dispatch_request_identity(request : DispatchRequest) -> String {
  request.dispatch_request_cid
}

///|
/// Durable uniqueness key for one language-task attempt. A new dispatch ID
/// cannot authorize concurrent execution of the same attempt.
pub fn dispatch_request_attempt_identity(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(16384, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, request.coordinator_authority)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, request.run_definition_cid)
    @encode.key(writer, "task_attempt")
    @encode.number_value(writer, request.task_attempt.to_double())
    @encode.key(writer, "task_key")
    @encode.string_value(writer, request.task_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-attempt-key/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
/// Exact durable-index columns. The canonical request remains authoritative;
/// this projection only lets a physical journal enforce uniqueness.
pub fn dispatch_request_journal_key(request : DispatchRequest) -> Array[String] {
  [
    request.coordinator_authority,
    request.site_key,
    request.site_generation.to_string(),
    request.dispatch_id,
    request.run_definition_cid,
    request.task_key,
    request.task_attempt.to_string(),
  ]
}
