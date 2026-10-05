///|
/// Registered finite codec profile for a Transfer-backed standard input. The
/// profile fixes manifest framing before any physical read: the existing
/// retained-row profile uses bare rows, while the standard export contract
/// uses ordered-array framing. Neither profile falls back to the other.
struct NativeRemoteStandardRowCodec {
  schema_contract_cid : String
  view_contract_cid : String
  codec_contract_cid : String
  framing : NativeRemoteStandardRowFraming
}

///|
priv enum NativeRemoteStandardRowFraming {
  BareRow
  OrderedArray
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
  framing : NativeRemoteStandardRowFraming
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
/// Dispatch-bound incremental input session. An asynchronous adapter may feed
/// physical frames, but it cannot replace the exact binding or open a Run
/// before the common verifier has established the captured source.
struct NativeRemoteStandardPhysicalRunAdmission {
  request : @remote.DispatchRequest
  binding : @remote.RemoteInputBinding
  input : NativeRemoteStandardTransferInput
  physical : NativeRemoteStandardPhysicalAdmission
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ]
  mut terminal : Bool
}

///|
/// Exact checked input semantics shared by synchronous native execution and
/// asynchronous environment Hosts. It contains no Run implementation.
struct NativeRemoteStandardDirectSourceFactory {
  codec : NativeRemoteStandardRowCodec
  sequence : @query.QuerySequence
  program : @context.ProgramSourceIdentity
  binding_limits : NativeRemoteStandardTransferBindingLimits
  source_limits : NativeRemoteStandardTransferSourceLimits
}

///|
/// Exact durable-Store input factory installed by one verified runtime
/// component. It fixes both the physical Store owner and every semantic input
/// parameter before a dispatch can enter runtime admission.
struct NativeRemoteStandardStoreRunFactory {
  journal : @transfer_journal.Journal
  root : @filesystem.Root
  codec : NativeRemoteStandardRowCodec
  sequence : @query.QuerySequence
  program : @context.ProgramSourceIdentity
  binding_limits : NativeRemoteStandardTransferBindingLimits
  source_limits : NativeRemoteStandardTransferSourceLimits
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ]
}

///|
/// One direct-input occurrence that establishes only the verified captured
/// source. The environment chooses no schema, view, codec, framing, or cleanup
/// transition while driving this session.
struct NativeRemoteStandardDirectSourceSession {
  input : NativeRemoteStandardTransferInput?
  mut admission : NativeRemoteStandardPhysicalAdmission?
  mut source : NativeRemoteStandardTransferSource?
  mut failure : NativeRemoteStandardInputFailure?
  mut terminal : Bool
}

///|
/// Exact checked task input factory installed by one verified runtime bundle.
/// Environment adapters cannot replace its codec, checked sequence, Program
/// identity, limits, or standard Run construction after registration.
struct NativeRemoteStandardDirectRunFactory {
  source : NativeRemoteStandardDirectSourceFactory
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ]
}

///|
/// One direct-input occurrence driven by an asynchronous environment adapter.
/// Feed rejection, cancellation, and the exact cleanup owner remain together
/// so the adapter cannot drop or replace a failed physical responsibility.
struct NativeRemoteStandardDirectRunSession {
  mut admission : NativeRemoteStandardPhysicalRunAdmission?
  mut failure : NativeRemoteStandardInputFailure?
  mut terminal : Bool
}

///|
priv struct NativeRemoteTransferSourceToken {
  physical : NativeRemoteStandardPhysicalSource
  mut active : Bool
  mut released : Bool
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
  let framing = if codec_contract_cid ==
    @execution.ordered_rows_canonical_contract_cid() {
    OrderedArray
  } else {
    BareRow
  }
  Ok({ schema_contract_cid, view_contract_cid, codec_contract_cid, framing, })
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
    cleanup_complete: false,
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
  let bytes = match admission.framing {
    BareRow => admission.row
    OrderedArray => {
      if admission.row_count == 0 {
        if admission.row != [91, 93] {
          return Err(InvalidProfile)
        }
        return Ok(())
      }
      let count = admission.row.length()
      let prefix : Byte = if admission.current == 0 { 91 } else { 44 }
      let last = admission.current == admission.expected_lengths.length() - 1
      let suffix = if last { 1 } else { 0 }
      if count <= 1 + suffix ||
        admission.row[0] != prefix ||
        (last && admission.row[count - 1] != 93) {
        return Err(InvalidProfile)
      }
      Array::makei(count - 1 - suffix, index => admission.row[index + 1])
    }
  }
  append_transfer_source_row(admission.output, bytes, admission.limits.wire)
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
  let token : NativeRemoteTransferSourceToken = {
    physical,
    active: true,
    released: false,
  }
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
    let expected_rows = if codec.framing is OrderedArray && row_count == 0 {
      0
    } else {
      1
    }
    if rows != expected_rows ||
      byte_lengths[index] < 0L ||
      byte_lengths[index] > limits.wire.max_bytes.to_int64() {
      return Err(transfer_source_failure(Some(token), InvalidProfile))
    }
    wire_bytes = wire_bytes + byte_lengths[index]
    if wire_bytes > limits.max_wire_bytes.to_int64() {
      return Err(transfer_source_failure(Some(token), Limit))
    }
  }
  let expected_chunks = if codec.framing is OrderedArray && row_count == 0 {
    1
  } else {
    row_count
  }
  if row_counts.length() != expected_chunks ||
    (row_count == 0 && codec.framing is OrderedArray && byte_lengths[0] != 2L) {
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
    framing: codec.framing,
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
  if admission.expected_lengths.is_empty() {
    if admission.current != -1 {
      return Err(cancel_transfer_source_admission(admission, InvalidProfile))
    }
  } else {
    if admission.current != admission.expected_lengths.length() - 1 {
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
fn bind_native_remote_standard_transfer_source_run(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  source : NativeRemoteStandardTransferSource,
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  let compute = match
    open_run(native_remote_standard_transfer_captured_source(source)) {
    Ok(value) => value
    Err(_) =>
      return Err({
        code: "standard-run-open",
        cleanup: () => finish_native_remote_standard_transfer_source(source),
        cleanup_complete: false,
      })
  }
  let owner = prepare_native_remote_standard_captured_run_owner(
    compute.run,
    compute.finish_output_owner,
    () => finish_native_remote_standard_transfer_source(source),
  )
  match bind_native_remote_standard_run(request, binding, owner) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err({
        code: "standard-run-binding",
        cleanup: () => owner.release(),
        cleanup_complete: false,
      })
  }
}

///|
/// Starts one exact dispatch-bound incremental input session. Preparation
/// performs no physical reads and opens no standard Run.
pub fn prepare_native_remote_standard_physical_run_admission(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  input : NativeRemoteStandardTransferInput,
  physical : NativeRemoteStandardPhysicalSource,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[
  NativeRemoteStandardPhysicalRunAdmission,
  NativeRemoteStandardInputFailure,
] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) ||
    @remote.remote_input_binding_cid(input.binding) !=
    @remote.remote_input_binding_cid(binding) {
    return Err({
      code: "foreign-input-binding",
      cleanup: physical.release,
      cleanup_complete: false,
    })
  }
  let admission = match
    prepare_native_remote_standard_physical_admission(
      input, physical, codec, sequence, program, source_limits,
    ) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  Ok({
    request,
    binding,
    input,
    physical: admission,
    open_run,
    terminal: false,
  })
}

///|
/// Checks one current direct-receiver claim against the exact Transfer input
/// fixed by a dispatch-bound session. This is rechecked before and after the
/// environment adapter streams bytes; possession of a retained body alone is
/// not input authority.
pub fn native_remote_standard_direct_run_admission_authorizes(
  admission : NativeRemoteStandardPhysicalRunAdmission,
  request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Bool {
  if admission.terminal ||
    @transfer.request_cid(request) !=
    @transfer.request_cid(admission.input.request) ||
    @transfer.destination_receipt_cid(receipt) !=
    admission.input.destination_receipt_cid ||
    @transfer.destination_receipt_json(receipt) is Err(_) {
    return false
  }
  let receipt_projection = @transfer.destination_receipt_projection(receipt)
  receipt_projection.length() == 7 &&
  receipt_projection[1] == @transfer.request_cid(request) &&
  transfer_source_live(admission.physical.token)
}

///|
fn prepare_native_remote_standard_direct_source_admission(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  claimed_request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  available : () -> Bool,
  release : () -> Bool,
  factory : NativeRemoteStandardDirectSourceFactory,
) -> Result[
  (NativeRemoteStandardTransferInput, NativeRemoteStandardPhysicalAdmission),
  NativeRemoteStandardInputFailure,
] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err({
      code: "foreign-input-binding",
      cleanup: () => true,
      cleanup_complete: false,
    })
  }
  let input = match
    admit_native_remote_standard_transfer_input(
      binding,
      factory.binding_limits.max_binding_bytes,
      factory.binding_limits.max_chunks,
      factory.binding_limits.max_manifest_bytes,
      factory.binding_limits.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err({
        code: "transfer-input-binding",
        cleanup: () => true,
        cleanup_complete: false,
      })
  }
  let receipt_projection = @transfer.destination_receipt_projection(receipt)
  if @transfer.request_cid(claimed_request) !=
    @transfer.request_cid(input.request) ||
    @transfer.destination_receipt_cid(receipt) != input.destination_receipt_cid ||
    @transfer.destination_receipt_json(receipt) is Err(_) ||
    receipt_projection.length() != 7 ||
    receipt_projection[1] != @transfer.request_cid(claimed_request) {
    return Err({
      code: "foreign-direct-transfer",
      cleanup: () => true,
      cleanup_complete: false,
    })
  }
  let physical = register_native_remote_standard_physical_source(
    input,
    available,
    (_max_bytes, _emit) => Err("incremental-provider-only"),
    release,
  )
  prepare_native_remote_standard_physical_admission(
    input,
    physical,
    factory.codec,
    factory.sequence,
    factory.program,
    factory.source_limits,
  ).map(admission => (input, admission))
}

///|
/// Starts the product direct-receiver session from one already-admitted
/// dispatch binding and its current retained claim. The environment owns only
/// asynchronous byte access and physical lifetime observations.
pub fn prepare_native_remote_standard_direct_run_admission(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  claimed_request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  available : () -> Bool,
  release : () -> Bool,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[
  NativeRemoteStandardPhysicalRunAdmission,
  NativeRemoteStandardInputFailure,
] {
  let source_factory : NativeRemoteStandardDirectSourceFactory = {
    codec,
    sequence,
    program,
    binding_limits,
    source_limits,
  }
  match
    prepare_native_remote_standard_direct_source_admission(
      request, binding, claimed_request, receipt, available, release, source_factory,
    ) {
    Ok((input, physical)) =>
      Ok({ request, binding, input, physical, open_run, terminal: false, })
    Err(failure) => Err(failure)
  }
}

///|
fn valid_native_remote_standard_direct_source_limits(
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
) -> Bool {
  binding_limits.max_binding_bytes >= 0 &&
  binding_limits.max_chunks >= 0 &&
  binding_limits.max_manifest_bytes >= 0 &&
  binding_limits.max_referenced_bytes >= 0L &&
  source_limits.max_rows >= 0 &&
  source_limits.max_wire_bytes >= 0 &&
  source_limits.max_read_bytes > 0 &&
  source_limits.max_entries >= 0 &&
  source_limits.max_name_bytes >= 0
}

///|
/// Registers one exact checked input factory without selecting an environment
/// Run implementation. Registration performs no physical access or reserve.
pub fn register_native_remote_standard_direct_source_factory(
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
) -> Result[
  NativeRemoteStandardDirectSourceFactory,
  NativeRemoteStandardHostIssue,
] {
  if !valid_native_remote_standard_direct_source_limits(
      binding_limits, source_limits,
    ) {
    return Err(InvalidConfiguration)
  }
  Ok({ codec, sequence, program, binding_limits, source_limits, })
}

///|
/// Registers one exact durable-Store task input factory. Registration does
/// not pin a generation or open a Run; those physical operations occur only
/// after the runtime admits an exact dispatch and input binding.
pub fn register_native_remote_standard_store_run_factory(
  journal : @transfer_journal.Journal,
  root : @filesystem.Root,
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[NativeRemoteStandardStoreRunFactory, NativeRemoteStandardHostIssue] {
  if !valid_native_remote_standard_direct_source_limits(
      binding_limits, source_limits,
    ) {
    return Err(InvalidConfiguration)
  }
  Ok({
    journal,
    root,
    codec,
    sequence,
    program,
    binding_limits,
    source_limits,
    open_run,
  })
}

///|
/// Registers one exact checked task input factory. Registration is pure and
/// performs no physical access, reservation, or Run construction.
pub fn register_native_remote_standard_direct_run_factory(
  codec : NativeRemoteStandardRowCodec,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
  binding_limits : NativeRemoteStandardTransferBindingLimits,
  source_limits : NativeRemoteStandardTransferSourceLimits,
  open_run : (@query.CapturedInputSource) -> Result[
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[NativeRemoteStandardDirectRunFactory, NativeRemoteStandardHostIssue] {
  let source = match
    register_native_remote_standard_direct_source_factory(
      codec, sequence, program, binding_limits, source_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, open_run, })
}

///|
/// Resolves the exact Transfer request selected by one registered task before
/// the environment acquires a direct-receiver claim.
pub fn native_remote_standard_direct_source_factory_request_cid(
  factory : NativeRemoteStandardDirectSourceFactory,
  binding : @remote.RemoteInputBinding,
) -> Result[String, NativeRemoteStandardInputFailure] {
  match
    admit_native_remote_standard_transfer_input(
      binding,
      factory.binding_limits.max_binding_bytes,
      factory.binding_limits.max_chunks,
      factory.binding_limits.max_manifest_bytes,
      factory.binding_limits.max_referenced_bytes,
    ) {
    Ok(input) => Ok(@transfer.request_cid(input.request))
    Err(_) =>
      Err({
        code: "transfer-input-binding",
        cleanup: () => true,
        cleanup_complete: false,
      })
  }
}

///|
pub fn native_remote_standard_direct_run_factory_request_cid(
  factory : NativeRemoteStandardDirectRunFactory,
  binding : @remote.RemoteInputBinding,
) -> Result[String, NativeRemoteStandardInputFailure] {
  native_remote_standard_direct_source_factory_request_cid(
    factory.source,
    binding,
  )
}

///|
/// Opens one direct source session without selecting an environment Run.
pub fn NativeRemoteStandardDirectSourceFactory::start_session(
  self : NativeRemoteStandardDirectSourceFactory,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  claimed_request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  available : () -> Bool,
  release : () -> Bool,
) -> NativeRemoteStandardDirectSourceSession {
  match
    prepare_native_remote_standard_direct_source_admission(
      request, binding, claimed_request, receipt, available, release, self,
    ) {
    Ok((input, admission)) =>
      {
        input: Some(input),
        admission: Some(admission),
        source: None,
        failure: None,
        terminal: false,
      }
    Err(failure) =>
      {
        input: None,
        admission: None,
        source: None,
        failure: Some(failure),
        terminal: true,
      }
  }
}

///|
/// Rechecks the exact retained direct claim for this unfinished source.
pub fn NativeRemoteStandardDirectSourceSession::authorizes(
  self : NativeRemoteStandardDirectSourceSession,
  request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Bool {
  if self.terminal {
    return false
  }
  guard self.input is Some(input) else { return false }
  guard self.admission is Some(admission) else { return false }
  if @transfer.request_cid(request) != @transfer.request_cid(input.request) ||
    @transfer.destination_receipt_cid(receipt) != input.destination_receipt_cid ||
    @transfer.destination_receipt_json(receipt) is Err(_) {
    return false
  }
  let receipt_projection = @transfer.destination_receipt_projection(receipt)
  receipt_projection.length() == 7 &&
  receipt_projection[1] == @transfer.request_cid(request) &&
  transfer_source_live(admission.token)
}

///|
/// Feeds one bounded physical frame into the common source verifier.
pub fn NativeRemoteStandardDirectSourceSession::feed(
  self : NativeRemoteStandardDirectSourceSession,
  index : Int,
  bytes : Bytes,
) -> Bool {
  if self.terminal {
    return false
  }
  guard self.admission is Some(admission) else { return false }
  match
    feed_native_remote_standard_physical_admission(admission, index, bytes) {
    Ok(_) => true
    Err(issue) => {
      self.failure = Some(cancel_transfer_source_admission(admission, issue))
      self.admission = None
      self.terminal = true
      false
    }
  }
}

///|
/// Establishes the captured source after complete physical verification.
pub fn NativeRemoteStandardDirectSourceSession::finish(
  self : NativeRemoteStandardDirectSourceSession,
) -> Result[
  NativeRemoteStandardTransferSource,
  NativeRemoteStandardInputFailure,
] {
  if self.terminal {
    return match self.failure {
      Some(failure) => Err(failure)
      None => Err(transfer_source_failure(None, InvalidProfile))
    }
  }
  guard self.admission is Some(admission) else {
    return Err(transfer_source_failure(None, InvalidProfile))
  }
  self.admission = None
  self.terminal = true
  match finish_native_remote_standard_physical_admission(admission) {
    Ok(source) => {
      self.source = Some(source)
      Ok(source)
    }
    Err(failure) => {
      self.failure = Some(failure)
      Err(failure)
    }
  }
}

///|
/// Cancels the unfinished source or returns its existing cleanup owner.
pub fn NativeRemoteStandardDirectSourceSession::cancel(
  self : NativeRemoteStandardDirectSourceSession,
) -> NativeRemoteStandardInputFailure {
  match self.failure {
    Some(failure) => failure
    None =>
      match self.admission {
        Some(admission) => {
          let failure = cancel_native_remote_standard_physical_admission(
            admission,
          )
          self.admission = None
          self.failure = Some(failure)
          self.terminal = true
          failure
        }
        None =>
          match self.source {
            Some(source) => {
              let failure = prepare_native_remote_standard_input_failure(
                "standard-source-release",
                () => finish_native_remote_standard_transfer_source(source),
              ).unwrap()
              self.failure = Some(failure)
              failure
            }
            None => transfer_source_failure(None, Physical("cancelled"))
          }
      }
  }
}

///|
/// Starts a direct input session using only the semantics fixed by the exact
/// registered factory.
pub fn NativeRemoteStandardDirectRunFactory::prepare(
  self : NativeRemoteStandardDirectRunFactory,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  claimed_request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  available : () -> Bool,
  release : () -> Bool,
) -> Result[
  NativeRemoteStandardPhysicalRunAdmission,
  NativeRemoteStandardInputFailure,
] {
  prepare_native_remote_standard_direct_run_admission(
    request,
    binding,
    claimed_request,
    receipt,
    available,
    release,
    self.source.codec,
    self.source.sequence,
    self.source.program,
    self.source.binding_limits,
    self.source.source_limits,
    self.open_run,
  )
}

///|
/// Opens one opaque direct-input session. Preparation failures are retained in
/// the returned owner rather than raised across the environment boundary.
pub fn NativeRemoteStandardDirectRunFactory::start_session(
  self : NativeRemoteStandardDirectRunFactory,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  claimed_request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  available : () -> Bool,
  release : () -> Bool,
) -> NativeRemoteStandardDirectRunSession {
  match
    self.prepare(request, binding, claimed_request, receipt, available, release) {
    Ok(admission) =>
      { admission: Some(admission), failure: None, terminal: false, }
    Err(failure) => { admission: None, failure: Some(failure), terminal: true, }
  }
}

///|
/// Reports whether the current receiver claim remains authorized for this
/// exact unfinished session.
pub fn NativeRemoteStandardDirectRunSession::authorizes(
  self : NativeRemoteStandardDirectRunSession,
  request : @transfer.RemoteTransferRequest,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Bool {
  if self.terminal {
    return false
  }
  guard self.admission is Some(admission) else { return false }
  native_remote_standard_direct_run_admission_authorizes(
    admission, request, receipt,
  )
}

///|
/// Feeds one bounded frame. A rejected frame atomically moves the exact input
/// owner into the session's failed cleanup state.
pub fn NativeRemoteStandardDirectRunSession::feed(
  self : NativeRemoteStandardDirectRunSession,
  index : Int,
  bytes : Bytes,
) -> Bool {
  if self.terminal {
    return false
  }
  guard self.admission is Some(admission) else { return false }
  match
    feed_native_remote_standard_physical_run_admission(admission, index, bytes) {
    Ok(_) => true
    Err(_) => {
      self.failure = Some(
        cancel_native_remote_standard_physical_run_admission(admission),
      )
      self.admission = None
      self.terminal = true
      false
    }
  }
}

///|
/// Finalizes verified input and opens the exact standard Run. Any failure is
/// retained for the same session's cleanup retry.
pub fn NativeRemoteStandardDirectRunSession::finish(
  self : NativeRemoteStandardDirectRunSession,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if self.terminal {
    return match self.failure {
      Some(failure) => Err(failure)
      None => Err(transfer_source_failure(None, InvalidProfile))
    }
  }
  guard self.admission is Some(admission) else {
    return Err(transfer_source_failure(None, InvalidProfile))
  }
  self.admission = None
  self.terminal = true
  match finish_native_remote_standard_physical_run_admission(admission) {
    Ok(value) => Ok(value)
    Err(failure) => {
      self.failure = Some(failure)
      Err(failure)
    }
  }
}

///|
/// Cancels an unfinished session or returns its already-owned failure.
pub fn NativeRemoteStandardDirectRunSession::cancel(
  self : NativeRemoteStandardDirectRunSession,
) -> NativeRemoteStandardInputFailure {
  match self.failure {
    Some(failure) => failure
    None =>
      match self.admission {
        Some(admission) => {
          let failure = cancel_native_remote_standard_physical_run_admission(
            admission,
          )
          self.admission = None
          self.failure = Some(failure)
          self.terminal = true
          failure
        }
        None => transfer_source_failure(None, Physical("cancelled"))
      }
  }
}

///|
/// Feeds one bounded frame into a dispatch-bound input session.
pub fn feed_native_remote_standard_physical_run_admission(
  admission : NativeRemoteStandardPhysicalRunAdmission,
  index : Int,
  bytes : Bytes,
) -> Result[Unit, NativeRemoteStandardTransferSourceIssue] {
  if admission.terminal {
    return Err(InvalidProfile)
  }
  feed_native_remote_standard_physical_admission(
    admission.physical,
    index,
    bytes,
  )
}

///|
/// Establishes the captured source, then and only then opens and binds the
/// exact standard Run.
pub fn finish_native_remote_standard_physical_run_admission(
  admission : NativeRemoteStandardPhysicalRunAdmission,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if admission.terminal {
    return Err(transfer_source_failure(None, InvalidProfile))
  }
  admission.terminal = true
  let source = match
    finish_native_remote_standard_physical_admission(admission.physical) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  bind_native_remote_standard_transfer_source_run(
    admission.request,
    admission.binding,
    source,
    admission.open_run,
  )
}

///|
/// Cancels one unfinished dispatch-bound input session. The returned failure
/// retains the exact physical cleanup owner for common runtime retry.
pub fn cancel_native_remote_standard_physical_run_admission(
  admission : NativeRemoteStandardPhysicalRunAdmission,
) -> NativeRemoteStandardInputFailure {
  if admission.terminal {
    return transfer_source_failure(None, Physical("cancelled"))
  }
  admission.terminal = true
  cancel_transfer_source_admission(admission.physical, Physical("cancelled"))
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
  if owner.token.released {
    return true
  }
  if (owner.token.physical.release)() {
    owner.token.released = true
    true
  } else {
    false
  }
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
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  let admission = match
    prepare_native_remote_standard_physical_run_admission(
      request, binding, input, physical, codec, sequence, program, source_limits,
      open_run,
    ) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let streamed = (physical.stream)(source_limits.max_read_bytes, fn(
    index,
    bytes,
  ) {
    feed_native_remote_standard_physical_run_admission(admission, index, bytes).map_err(_ => {
        "physical-admission"
      },
    )
  })
  match streamed {
    Ok(_) => ()
    Err(_) => {
      let failure = cancel_native_remote_standard_physical_run_admission(
        admission,
      )
      return Err({
        code: native_remote_standard_input_failure_code(failure),
        cleanup: () => {
          retry_native_remote_standard_input_failure_cleanup(failure)
        },
        cleanup_complete: false,
      })
    }
  }
  finish_native_remote_standard_physical_run_admission(admission)
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
    NativeRemoteStandardComputeOwner,
    Unit,
  ],
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err({
      code: "foreign-input-binding",
      cleanup: () => true,
      cleanup_complete: false,
    })
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
      return Err({
        code: "transfer-input-binding",
        cleanup: () => true,
        cleanup_complete: false,
      })
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

///|
/// Resolves one admitted dispatch through the exact durable-Store factory.
/// Application composition cannot replace the Store, codec, checked Program
/// identity, bounds, or Run constructor selected for this task.
pub fn NativeRemoteStandardStoreRunFactory::resolve(
  self : NativeRemoteStandardStoreRunFactory,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  resolve_native_remote_standard_transfer_run(
    request,
    binding,
    self.journal,
    self.root,
    self.codec,
    self.sequence,
    self.program,
    self.binding_limits,
    self.source_limits,
    self.open_run,
  )
}
