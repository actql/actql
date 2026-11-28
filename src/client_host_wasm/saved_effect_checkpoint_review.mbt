///|
const SAVED_EFFECT_CHECKPOINT_REVIEW_KIND : Int = 15

///|
const SAVED_EFFECT_REVIEW_RESULT_MAX : Int = 65536

///|
const SAVED_EFFECT_REVIEW_PRIVATE_MAX : Int = 1048576

///|
fn produce_saved_effect_checkpoint_review(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.produced {
    return validate_saved_effect_checkpoint_review(value, record, configuration)
  }
  if record.invoked || record.output_closed {
    return -33
  }
  record.invoked = true
  let bytes = match
    select_saved_effect_checkpoint_review(value, record, configuration) {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, bytes),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn validate_saved_effect_checkpoint_review(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  match select_saved_effect_checkpoint_review(value, record, configuration) {
    Ok(bytes) if @buffers.buffer_wire(value.pool, record.slot) == Some(bytes) =>
      0
    Ok(_) => -32
    Err(code) => code
  }
}

///|
fn select_saved_effect_checkpoint_review(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  let check = () => submission_lookup_current(value, record, configuration)
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  guard configuration.mock_project is Some(_) &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) &&
    current.generation is Some((device, inode)) &&
    record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) &&
    packet.length() >= 76 &&
    packet.length() <=
    2 * SAVED_EFFECT_REVIEW_PRIVATE_MAX +
    (if record.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND { 5 } else { 3 }) *
    65536 +
    132 &&
    record.append_plan is Idle else {
    return Err(-32)
  }
  if physical_journal_schema(current.physical) != 1 {
    return Err(-41)
  }
  let resolving = record.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND
  let stage = if resolving { 2 } else { packet[71].to_int() }
  if stage == 1 || stage == 2 || stage == 4 {
    let tuple : @authorization.AccessTuple = {
      principal: configuration.tuple.principal,
      connection: configuration.tuple.connection,
      resource: "run",
      operation: "resolve",
    }
    if !(@authorization.evaluate_account(configuration.account, tuple)
      is @authorization.Allow(_)) {
      return Err(-32)
    }
  }
  guard sdk_journal_writer_capacity(4096, 8, 2) is Some(binding_quote) else {
    return Err(-4)
  }
  let wrapper = if resolving {
    3L * packet.length().to_int64() + 4096L
  } else {
    0L
  }
  let fixed = binding_quote + 8L * 262144L + wrapper
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  record.append_plan = Decoding(capacity, Idle)
  let unwrap = if resolving {
    saved_effect_resolution_proof_input(packet)
  } else {
    Some((packet, None))
  }
  guard unwrap is Some((packet, resolution)) else { return Err(-31) }
  let extent = mock_effect_descriptor_field(packet, 72)
  guard stage <= 4 &&
    extent > 0 &&
    extent <= SAVED_EFFECT_REVIEW_RESULT_MAX &&
    ((stage != 0 && stage != 4) || packet.length() == 76) else {
    return Err(-31)
  }
  let challenge = if resolution is Some(input) {
    Some((review, fund) => {
      prepare_saved_effect_resolution_proof(
        value, record, configuration, current, capacity, input, review, check, fund,
      )
    })
  } else {
    None
  }
  let selected = project_saved_effect_checkpoint_review(
    value, current, configuration, packet, stage, extent, device, inode, sdk, check,
    fixed, capacity, challenge,
  )
  if record.append_plan is EffectProof(_) {
    return selected
  }
  let returned = close_submission_decode_prefix(value, record)
  selected.bind(bytes => {
    if returned == 0 {
      check().map(_ => bytes)
    } else {
      Err(returned)
    }
  })
}

///|
fn project_saved_effect_checkpoint_review(
  value : Instance,
  current : StoredHostCurrent,
  configuration : StoredRunConfiguration,
  packet : Bytes,
  stage : Int,
  extent : Int,
  device : UInt64,
  inode : UInt64,
  sdk : StoredSDKRunConfiguration,
  check : () -> Result[Unit, Int],
  fixed : Int64,
  capacity : @resources.CapacityReservation,
  challenge : ((
    @host.ClientEffectSavedReviewConfirmation,
    (Int, Int, Int) -> Result[Unit, Int],
  ) -> Result[Bytes, Int])?,
) -> Result[Bytes, Int] {
  let selected = @utf8.decode(packet[:71]) catch { _ => return Err(-31) }
  guard @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(binding) else {
    return Err(-32)
  }
  let peak = Ref(fixed)
  let grow = (total : Int64) => {
    if total <= peak.val {
      return true
    }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, total)
      is Err(_) {
      return false
    }
    peak.val = total
    true
  }
  let retained = Ref(0L)
  let fund = (bytes : Int, nodes : Int, _ : Int) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((scratch, _)) &&
      @execution.checked_preparation_add_product(fixed, retained.val, 1L)
      is Some(base) &&
      @execution.checked_preparation_add_product(base, scratch, 1L)
      is Some(total) &&
      grow(total) else {
      return Err(-4)
    }
    Ok(())
  }
  let decode_run = (row : @host.ClientJournalPhysicalRow) => {
    let refused = Ref(false)
    let decoded = @host.decode_client_run_journal_row_with_observation_originals(
      row.body,
      before_construction=Some(stage => {
        guard @host.client_run_journal_decode_construction(stage)
          is Some((r, e)) &&
          @execution.checked_preparation_add_product(fixed, r, 1L) is Some(next) &&
          @execution.checked_preparation_add_product(next, e, 1L) is Some(total) &&
          grow(total) else {
          refused.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        retained.val = r
        Ok(())
      }),
    )
    match decoded {
      Ok((run, _, _)) => Ok(run)
      Err(_) => Err(if refused.val { -4 } else { -32 })
    }
  }
  match
    @host.select_client_waiting_effect_checkpoint_cid(
      configuration.run_namespace,
      configuration.authority_scope_cid,
      binding,
      selected,
      (table, key) => {
        physical_journal_row(current.physical, check, 1, table, key)
      },
      (table, key) => {
        physical_journal_row(current.physical, check, 0, table, key)
      },
      decode_run,
      -32,
      fund,
    ) {
    Err(code) => Err(code)
    Ok(None) => Err(-42)
    Ok(Some(original)) =>
      project_saved_effect_review_part(
        original, configuration, sdk, binding, packet, stage, extent, device, inode,
        fund, challenge,
      )
  }
}

///|
fn project_saved_effect_review_part(
  original : @host.ClientEffectWaitingOriginal,
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
  binding : String,
  packet : Bytes,
  stage : Int,
  extent : Int,
  device : UInt64,
  inode : UInt64,
  fund : (Int, Int, Int) -> Result[Unit, Int],
  challenge : ((
    @host.ClientEffectSavedReviewConfirmation,
    (Int, Int, Int) -> Result[Unit, Int],
  ) -> Result[Bytes, Int])?,
) -> Result[Bytes, Int] {
  match fund(12288, 128, 8) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let opening = original.review_opening(sdk.adoption_cid, binding)
  guard opening is Ok((_, continuation_cid, review_cid, preimage)) else {
    return Err(-32)
  }
  if stage == 0 || stage == 4 {
    return Ok(@utf8.encode(continuation_cid + review_cid) + preimage)
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  if stage == 3 {
    let bytes = packet.length() - 76
    if bytes <= 0 || bytes > extent {
      return Err(-31)
    }
    match fund(bytes, Int::min(max_nodes, bytes), max_depth) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    let wire = @utf8.decode(packet[76:]) catch { _ => return Err(-31) }
    return original
      .confirm_public_review(wire, extent, max_nodes, max_depth)
      .map(wire => @utf8.encode(wire))
      .map_err(_ => -32)
  }
  let length = packet.length()
  guard length >= (if stage == 1 { 80 } else { 96 }) else { return Err(-31) }
  let continuation_length = mock_effect_descriptor_field(packet, 76)
  guard continuation_length > 0 &&
    continuation_length <= SAVED_EFFECT_REVIEW_PRIVATE_MAX &&
    continuation_length <= length - 80 else {
    return Err(-31)
  }
  let next = 80 + continuation_length
  match fund(length, Int::min(max_nodes, length), max_depth) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let continuation = @utf8.decode(packet[80:next]) catch {
    _ => return Err(-31)
  }
  guard @host.admit_client_effect_saved_review_reference(
      original,
      continuation,
      SAVED_EFFECT_REVIEW_PRIVATE_MAX,
      max_nodes,
      max_depth,
    )
    is Ok(reference) else {
    return Err(-32)
  }
  if stage == 1 {
    guard next == length &&
      reference.holding_coordinates(
        sdk.store_authority_cid,
        configuration.run_namespace,
        device,
        inode,
      )
      is Ok((capture_key, capture_cid, preview_key, preview_cid)) else {
      return Err(-32)
    }
    return Ok(
      @utf8.encode(capture_key + capture_cid + preview_key + preview_cid),
    )
  }
  guard next <= length - 16 else { return Err(-31) }
  let checkpoint_length = mock_effect_descriptor_field(packet, next)
  let preview_length = mock_effect_descriptor_field(packet, next + 4)
  let capture_length = mock_effect_descriptor_field(packet, next + 8)
  let review_length = mock_effect_descriptor_field(packet, next + 12)
  guard checkpoint_length > 0 &&
    checkpoint_length <= 65536 &&
    preview_length > 0 &&
    preview_length <= 65536 &&
    capture_length > 0 &&
    capture_length <= SAVED_EFFECT_REVIEW_PRIVATE_MAX &&
    review_length > 0 &&
    review_length <= extent &&
    next +
    16 +
    checkpoint_length +
    preview_length +
    capture_length +
    review_length ==
    length else {
    return Err(-31)
  }
  let start = next + 16
  let preview_start = start + checkpoint_length
  let capture_start = preview_start + preview_length
  let checkpoint = @utf8.decode(packet[start:preview_start]) catch {
    _ => return Err(-31)
  }
  let preview = @utf8.decode(packet[preview_start:capture_start]) catch {
    _ => return Err(-31)
  }
  let review_start = capture_start + capture_length
  let capture = @utf8.decode(packet[capture_start:review_start]) catch {
    _ => return Err(-31)
  }
  let review = @utf8.decode(packet[review_start:]) catch {
    _ => return Err(-31)
  }
  if challenge is Some(prepare) {
    return reference
      .confirm_review_original(
        checkpoint,
        preview,
        capture,
        review,
        extent,
        SAVED_EFFECT_REVIEW_PRIVATE_MAX,
        max_nodes,
        max_depth,
      )
      .map_err(_ => -32)
      .bind(confirmed => prepare(confirmed, fund))
  }
  reference
  .confirm_review(
    checkpoint,
    preview,
    capture,
    review,
    extent,
    SAVED_EFFECT_REVIEW_PRIVATE_MAX,
    max_nodes,
    max_depth,
  )
  .map(wire => @utf8.encode(wire))
  .map_err(_ => -32)
}
