///|
/// Registered finite codec profile for a Transfer-backed standard input. The
/// first profile stores exactly one canonical retained-row wire per manifest
/// chunk; this is not a universal Transfer codec requirement.
struct NativeRemoteStandardRowCodec {
  schema_contract_cid : String
  view_contract_cid : String
  codec_contract_cid : String
}

///|
pub(all) struct NativeRemoteStandardTransferSourceLimits {
  max_rows : Int
  max_wire_bytes : Int
  max_read_bytes : Int
  max_entries : Int
  max_name_bytes : Int
  values : @execution.ValueLimits
  wire : @execution.RetainedRowDecodeLimits
}

///|
pub(all) struct NativeRemoteStandardTransferBindingLimits {
  max_binding_bytes : Int
  max_chunks : Int
  max_manifest_bytes : Int
  max_referenced_bytes : Int64
}

///|
/// A trusted physical provider for one exact Transfer destination. The
/// provider owns only physical streaming and lifetime observations; schema,
/// row-wire, completion, and capture decisions remain in this package.
struct NativeRemoteStandardPhysicalSource {
  request_cid : String
  input_binding_cid : String
  available : () -> Bool
  stream : (Int, (Int, Bytes) -> Result[Unit, String]) -> Result[Unit, String]
  release : () -> Bool
}

///|
/// Incremental physical admission used by asynchronous environment adapters.
/// The adapter supplies bounded frames and physical lifetime observations;
/// this owner alone decides framing, row admission, completion, and capture.
struct NativeRemoteStandardPhysicalAdmission {
  token : NativeRemoteTransferSourceToken
  sequence : @query.QuerySequence
  program : @context.ProgramSourceIdentity
  limits : NativeRemoteStandardTransferSourceLimits
  output : @execution.AdmittedOutput
  expected_lengths : Array[Int64]
  row_count : Int
  wire_bytes : Int64
  mut current : Int
  mut current_bytes : Int64
  mut row : Array[Byte]
  mut terminal : Bool
}

///|
priv struct NativeRemoteTransferSourceToken {
  physical : NativeRemoteStandardPhysicalSource
  mut active : Bool
}

///|
priv struct NativeRemoteTransferOutputEvidence {
  token : NativeRemoteTransferSourceToken
  rows : @execution.AdmittedOutputRows
}

///|
/// Exact captured source and reader owner produced by the registered Transfer
/// codec. Releasing it revokes the live completion before returning the durable
/// reader occurrence.
struct NativeRemoteStandardTransferSource {
  token : NativeRemoteTransferSourceToken
  source : @query.CapturedInputSource
}

///|
pub(all) enum NativeRemoteStandardTransferSourceIssue {
  InvalidProfile
  Limit
  Physical(String)
  Transfer(@transfer_client.NativeRemoteTransferClientIssue)
  Wire(@execution.AdmittedOutputWireIssue)
  Admission(@execution.CaptureIssue)
  Completion(@execution.TrustedOutputIssue)
  Capture(@query.CapturedSourceIssue)
}

///|
fn transfer_source_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < value.length(); index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
/// Registers the exact schema, logical view and physical codec contract tuple
/// accepted by one trusted standard-input implementation.
pub fn register_native_remote_standard_row_codec(
  schema_contract_cid : String,
  view_contract_cid : String,
  codec_contract_cid : String,
) -> Result[
  NativeRemoteStandardRowCodec,
  NativeRemoteStandardTransferSourceIssue,
] {
  if !transfer_source_cid(schema_contract_cid) ||
    !transfer_source_cid(view_contract_cid) ||
    !transfer_source_cid(codec_contract_cid) {
    return Err(InvalidProfile)
  }
  Ok({ schema_contract_cid, view_contract_cid, codec_contract_cid, })
}

///|
fn transfer_source_live(token : NativeRemoteTransferSourceToken) -> Bool {
  token.active && (token.physical.available)()
}

///|
fn transfer_source_failure(
  token : NativeRemoteTransferSourceToken?,
  issue : NativeRemoteStandardTransferSourceIssue,
) -> NativeRemoteStandardInputFailure {
  let code = match issue {
    InvalidProfile => "transfer-input-profile"
    Limit => "transfer-input-limit"
    Physical(_) => "transfer-input-material"
    Transfer(_) => "transfer-input-material"
    Wire(_) => "transfer-input-wire"
    Admission(_) => "transfer-input-admission"
    Completion(_) => "transfer-input-completion"
    Capture(_) => "transfer-input-capture"
  }
  {
    code,
    cleanup: fn() {
      match token {
        None => true
        Some(owner) => {
          owner.active = false
          (owner.physical.release)()
        }
      }
    },
  }
}

///|
/// Registers a physical provider already bound to one admitted Transfer
/// request. This is the provider SDK boundary for registered routes.
/// Callers are trusted only for physical access and stop observations; they
/// cannot supply logical rows, completion evidence, or output identity.
pub fn register_native_remote_standard_physical_source(
  input : NativeRemoteStandardTransferInput,
  available : () -> Bool,
  stream : (Int, (Int, Bytes) -> Result[Unit, String]) -> Result[Unit, String],
  release : () -> Bool,
) -> NativeRemoteStandardPhysicalSource {
  {
    request_cid: @transfer.request_cid(input.request),
    input_binding_cid: @remote.remote_input_binding_cid(input.binding),
    available,
    stream,
    release,
  }
}

///|
/// Pins and verifies the durable Store representation, then exposes it through
/// the same physical-provider boundary used by other registered routes.
fn pin_native_remote_standard_store_source(
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  input : NativeRemoteStandardTransferInput,
) -> Result[
  NativeRemoteStandardPhysicalSource,
  NativeRemoteStandardTransferSourceIssue,
] {
  let request = input.request
  let material = match
    @transfer_client.pin_durable_store_destination_material(
      journal,
      root,
      request,
      input.destination_use_id,
      @remote.remote_input_binding_cid(input.binding),
      input.destination_receipt_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  Ok(
    register_native_remote_standard_physical_source(
      input,
      () => @transfer_client.destination_material_use_available(material),
      (max_bytes, emit) => {
        @transfer_client.stream_destination_material_use(
          material, max_bytes, emit,
        ).map_err(_ => "store-stream")
      },
      () => {
        match @transfer_client.release_destination_material_use(material) {
          Ok(_) => true
          Err(_) => false
        }
      },
    ),
  )
}

///|
fn append_transfer_source_row(
  output : @execution.AdmittedOutput,
  bytes : Array[Byte],
  limits : @execution.RetainedRowDecodeLimits,
) -> Result[Unit, NativeRemoteStandardTransferSourceIssue] {
  let wire = @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => return Err(InvalidProfile)
  }
  match @execution.append_admitted_output_wire(output, wire, limits) {
    Ok(_) => Ok(())
    Err(issue) => Err(Wire(issue))
  }
}

///|
fn cancel_transfer_source_admission(
  admission : NativeRemoteStandardPhysicalAdmission,
  issue : NativeRemoteStandardTransferSourceIssue,
) -> NativeRemoteStandardInputFailure {
  if admission.terminal {
    return transfer_source_failure(None, issue)
  }
  admission.terminal = true
  ignore(@execution.cancel_admitted_output(admission.output))
  transfer_source_failure(Some(admission.token), issue)
}

///|
fn finish_transfer_source_admission_row(
  admission : NativeRemoteStandardPhysicalAdmission,
) -> Result[Unit, NativeRemoteStandardTransferSourceIssue] {
  if admission.current < 0 ||
    admission.current >= admission.expected_lengths.length() ||
    admission.current_bytes != admission.expected_lengths[admission.current] {
    return Err(InvalidProfile)
  }
  append_transfer_source_row(
    admission.output,
    admission.row,
    admission.limits.wire,
  )
}

///|
/// Prepares the common incremental verifier for one exact physical provider.
/// No physical bytes are read by this operation.
pub fn prepare_native_remote_standard_physical_admission(
  input : NativeRemoteStandardTransferInput,
  physical : NativeRemoteStandardPhysicalSource,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
) -> Result[
  NativeRemoteStandardPhysicalAdmission,
  NativeRemoteStandardInputFailure,
] {
  let request = input.request
  let token : NativeRemoteTransferSourceToken = { physical, active: true, }
  if limits.max_rows < 0 ||
    limits.max_wire_bytes < 0 ||
    limits.max_read_bytes <= 0 ||
    limits.max_entries < 0 ||
    limits.max_name_bytes < 0 {
    return Err(transfer_source_failure(Some(token), Limit))
  }
  if @transfer.request_schema_contract_cid(request) != codec.schema_contract_cid ||
    @transfer.request_view_contract_cid(request) != codec.view_contract_cid ||
    @transfer.request_codec_contract_cid(request) != codec.codec_contract_cid {
    return Err(transfer_source_failure(Some(token), InvalidProfile))
  }
  if physical.request_cid != @transfer.request_cid(request) ||
    physical.input_binding_cid !=
    @remote.remote_input_binding_cid(input.binding) ||
    !(physical.available)() {
    return Err(transfer_source_failure(Some(token), InvalidProfile))
  }
  let row_count = @transfer.request_row_count(request)
  let row_counts = @transfer.request_chunk_row_counts(request)
  let byte_lengths = @transfer.request_chunk_byte_lengths(request)
  if row_count > limits.max_rows || row_counts.length() != byte_lengths.length() {
    return Err(transfer_source_failure(Some(token), Limit))
  }
  let mut wire_bytes = 0L
  for index, rows in row_counts {
    if rows != 1 ||
      byte_lengths[index] < 0L ||
      byte_lengths[index] > limits.wire.max_bytes.to_int64() {
      return Err(transfer_source_failure(Some(token), InvalidProfile))
    }
    wire_bytes = wire_bytes + byte_lengths[index]
    if wire_bytes > limits.max_wire_bytes.to_int64() {
      return Err(transfer_source_failure(Some(token), Limit))
    }
  }
  if (row_count == 0 && !row_counts.is_empty()) ||
    row_count != row_counts.length() {
    return Err(transfer_source_failure(Some(token), InvalidProfile))
  }
  let output = match
    @execution.prepare_admitted_output(
      @query.query_sequence_owner(sequence),
      @pipeline.Step(1),
      row_count,
      limits.values,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(transfer_source_failure(Some(token), Admission(issue)))
  }
  Ok({
    token,
    sequence,
    program,
    limits,
    output,
    expected_lengths: byte_lengths,
    row_count,
    wire_bytes,
    current: -1,
    current_bytes: 0L,
    row: [],
    terminal: false,
  })
}

///|
/// Admits one bounded frame. Frames must preserve manifest chunk order and
/// exact byte length; a new chunk cannot begin before the previous row is
/// complete. The physical stream owns access-stop checks while it is active;
/// this verifier rechecks generation availability after the stream returns.
pub fn feed_native_remote_standard_physical_admission(
  admission : NativeRemoteStandardPhysicalAdmission,
  index : Int,
  bytes : Bytes,
) -> Result[Unit, NativeRemoteStandardTransferSourceIssue] {
  if admission.terminal ||
    index < 0 ||
    index >= admission.expected_lengths.length() ||
    bytes.length() > admission.limits.max_read_bytes {
    return Err(InvalidProfile)
  }
  if index != admission.current {
    if index != admission.current + 1 {
      return Err(InvalidProfile)
    }
    if admission.current >= 0 {
      match finish_transfer_source_admission_row(admission) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    admission.current = index
    admission.current_bytes = 0L
    admission.row = []
  }
  let incoming = bytes.length().to_int64()
  if admission.current_bytes > admission.expected_lengths[index] - incoming ||
    admission.row.length() > admission.limits.wire.max_bytes - bytes.length() {
    return Err(InvalidProfile)
  }
  for byte in bytes {
    admission.row.push(byte)
  }
  admission.current_bytes = admission.current_bytes + incoming
  Ok(())
}

///|
/// Completes physical verification and establishes the common captured source.
/// A failure retains the physical cleanup owner for explicit retry.
pub fn finish_native_remote_standard_physical_admission(
  admission : NativeRemoteStandardPhysicalAdmission,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteStandardInputFailure,
] {
  if admission.terminal {
    return Err(transfer_source_failure(None, InvalidProfile))
  }
  if !transfer_source_live(admission.token) {
    return Err(cancel_transfer_source_admission(admission, InvalidProfile))
  }
  if admission.row_count == 0 {
    if admission.current != -1 {
      return Err(cancel_transfer_source_admission(admission, InvalidProfile))
    }
  } else {
    if admission.current != admission.row_count - 1 {
      return Err(cancel_transfer_source_admission(admission, InvalidProfile))
    }
    match finish_transfer_source_admission_row(admission) {
      Ok(_) => ()
      Err(issue) =>
        return Err(cancel_transfer_source_admission(admission, issue))
    }
  }
  admission.terminal = true
  let rows = match @execution.finish_admitted_output(admission.output) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        transfer_source_failure(Some(admission.token), Admission(issue)),
      )
  }
  if @execution.admitted_output_row_count(rows) != admission.row_count {
    return Err(transfer_source_failure(Some(admission.token), InvalidProfile))
  }
  let evidence : NativeRemoteTransferOutputEvidence = {
    token: admission.token,
    rows,
  }
  let port = match
    @execution.prepare_trusted_output_port(
      @execution.generated_completion_preparation(
        @query.query_generated_sequence(admission.sequence),
      ),
      @pipeline.Step(1),
      admission.limits.max_entries,
      admission.limits.max_name_bytes,
      fn(proof : NativeRemoteTransferOutputEvidence) {
        if physical_equal(proof, evidence) && transfer_source_live(proof.token) {
          Some(proof.rows)
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        transfer_source_failure(Some(admission.token), Completion(issue)),
      )
  }
  let completed = match @execution.complete_trusted_output(port, evidence) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        transfer_source_failure(Some(admission.token), Completion(issue)),
      )
  }
  let capture = match
    @query.prepare_trusted_capture_port(admission.sequence, admission.program, fn(
      proof : NativeRemoteTransferOutputEvidence,
    ) {
      if physical_equal(proof, evidence) && transfer_source_live(proof.token) {
        Some((completed, admission.wire_bytes.to_int()))
      } else {
        None
      }
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(transfer_source_failure(Some(admission.token), Capture(issue)))
  }
  let source = match @query.capture_verified_source(capture, evidence) {
    Ok(value) => value
    Err(issue) =>
      return Err(transfer_source_failure(Some(admission.token), Capture(issue)))
  }
  Ok({ token: admission.token, source, })
}

///|
/// Cancels an unfinished incremental admission and returns its retryable
/// physical cleanup owner.
pub fn cancel_native_remote_standard_physical_admission(
  admission : NativeRemoteStandardPhysicalAdmission,
) -> NativeRemoteStandardInputFailure {
  cancel_transfer_source_admission(admission, Physical("cancelled"))
}

///|
/// Verifies and decodes one exact registered physical destination into a
/// provisional output. Completion and capture are established only through
/// the fixed provider verifiers below, after the full physical stream succeeds.
pub fn acquire_native_remote_standard_physical_source(
  input : NativeRemoteStandardTransferInput,
  physical : NativeRemoteStandardPhysicalSource,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteStandardInputFailure,
] {
  let admission = match
    prepare_native_remote_standard_physical_admission(
      input, physical, codec, sequence, program, limits,
    ) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let streamed = (physical.stream)(limits.max_read_bytes, fn(index, bytes) {
    feed_native_remote_standard_physical_admission(admission, index, bytes).map_err(_ => {
        "physical-admission"
      },
    )
  })
  match streamed {
    Ok(_) => ()
    Err(issue) =>
      return Err(cancel_transfer_source_admission(admission, Physical(issue)))
  }
  finish_native_remote_standard_physical_admission(admission)
}

///|
/// Pins the exact committed Store-route destination and passes it through the
/// common registered physical-source verifier.
pub fn acquire_native_remote_standard_transfer_source(
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  input : NativeRemoteStandardTransferInput,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  limits : NativeRemoteStandardTransferSourceLimits,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteStandardInputFailure,
] {
  let physical = match
    pin_native_remote_standard_store_source(journal, root, input) {
    Ok(value) => value
    Err(issue) => return Err(transfer_source_failure(None, issue))
  }
  match
    acquire_native_remote_standard_physical_source(
      input, physical, codec, sequence, program, limits,
    ) {
    Ok(value) => Ok(value)
    Err(failure) => Err(failure)
  }
}

///|
pub fn native_remote_standard_transfer_captured_source(
  owner : NativeRemoteStandardTransferSource,
) -> @query.CapturedInputSource {
  owner.source
}

///|
/// Revokes the source before releasing its exact durable reader occurrence.
/// A false result keeps the cleanup owner retryable.
pub fn finish_native_remote_standard_transfer_source(
  owner : NativeRemoteStandardTransferSource,
) -> Bool {
  owner.token.active = false
  (owner.token.physical.release)()
}

///|
/// Product resolver for a registered physical provider. It admits only the
/// exact dispatch-bound input and gives the provider's verified captured
/// source to the task-specific standard-Run factory.
pub fn resolve_native_remote_standard_physical_run(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  input : NativeRemoteStandardTransferInput,
  physical : NativeRemoteStandardPhysicalSource,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    @native_host.NativeStandardStrategyRun,
    Unit,
  ],
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) ||
    @remote.remote_input_binding_cid(input.binding) !=
    @remote.remote_input_binding_cid(binding) {
    return Err({ code: "foreign-input-binding", cleanup: physical.release, })
  }
  let source = match
    acquire_native_remote_standard_physical_source(
      input, physical, codec, sequence, program, source_limits,
    ) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let run = match
    open_run(native_remote_standard_transfer_captured_source(source)) {
    Ok(value) => value
    Err(_) =>
      return Err({
        code: "standard-run-open",
        cleanup: () => finish_native_remote_standard_transfer_source(source),
      })
  }
  match
    bind_native_remote_standard_run(request, binding, run, () => {
      finish_native_remote_standard_transfer_source(source)
    }) {
    Ok(value) => Ok(value)
    Err(_) => {
      let closed = [false]
      Err({
        code: "standard-run-binding",
        cleanup: fn() {
          if !closed[0] {
            match @native_host.close_native_standard_strategy_run(run) {
              Ok(true) => closed[0] = true
              Ok(false) | Err(_) => return false
            }
          }
          finish_native_remote_standard_transfer_source(source)
        },
      })
    }
  }
}

///|
/// Product resolver for the durable Store provider. It re-admits the canonical
/// binding, pins the exact destination, and delegates every semantic decision
/// to the common registered physical-source resolver.
pub fn resolve_native_remote_standard_transfer_run(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    @native_host.NativeStandardStrategyRun,
    Unit,
  ],
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err({ code: "foreign-input-binding", cleanup: () => true, })
  }
  let input = match
    admit_native_remote_standard_transfer_input(
      binding,
      binding_limits.max_binding_bytes,
      binding_limits.max_chunks,
      binding_limits.max_manifest_bytes,
      binding_limits.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err({ code: "transfer-input-binding", cleanup: () => true, })
  }
  let physical = match
    pin_native_remote_standard_store_source(journal, root, input) {
    Ok(value) => value
    Err(issue) => return Err(transfer_source_failure(None, issue))
  }
  resolve_native_remote_standard_physical_run(
    request, binding, input, physical, codec, sequence, program, source_limits, open_run,
  )
}
