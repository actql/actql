///|
/// Native storage for the existing Local materializing dispatch. The common
/// attempt is already reserved when this owner is constructed; its complete
/// callback is invoked only after the exact output file has been sealed.
priv struct NativeStrategyLocalOwner {
  operations : @local_driver.LocalDispatchOperations
  file : @retained_file.NativeRetainedTaskFile
  wire : @execution.RowWireLimits
  max_batch_bytes : Int
  mut representation : @local_driver.LocalRetainedRepresentation?
  mut settled : Bool
  mut closed : Bool
  mut released : Bool
}

///|
/// The common attempt already exists when creating its file fails. Keep the
/// attempt reachable until disposal and settlement are both confirmed.
priv struct NativeStrategyUnfiledLocalOwner {
  operations : @local_driver.LocalDispatchOperations
  mut closed : Bool
  mut settled : Bool
}

///|
fn close_native_strategy_unfiled_local_owner(
  owner : NativeStrategyUnfiledLocalOwner,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  if !owner.closed {
    (owner.operations.close)()
    owner.closed = true
  }
  if !owner.settled {
    match (owner.operations.settle)() {
      Ok(_) => owner.settled = true
      Err(_) => return Err(LocalCleanup)
    }
  }
  Ok(true)
}

///|
pub(all) enum NativeStrategyLocalIssue {
  MissingOutput
  InvalidState
  Dispatch(@duckdb_standard_host.DispatchIssue)
  RetainedFile(@retained_file.NativeRetainedTaskFileIssue)
  RowFrames(@publication.DurableResultRowFrameIssue)
}

///|
fn start_native_strategy_local_owner(
  operations : @local_driver.LocalDispatchOperations,
  profile : NativeStrategyRetainedOutputProfile,
  task : Int,
) -> Result[NativeStrategyLocalOwner, NativeStrategyLocalIssue] {
  guard operations.output is Some(_) &&
    profile.root_path != "" &&
    profile.run_occurrence != "" &&
    profile.max_file_bytes > 0L else {
    return Err(MissingOutput)
  }
  let file = @retained_file.begin_native_retained_task_file(
    profile.root_path,
    profile.run_occurrence + "-task-" + task.to_string(),
    profile.max_file_bytes,
  ).map_err(issue => NativeStrategyLocalIssue::RetainedFile(issue))
  file.map(file => {
    operations,
    file,
    wire: profile.wire,
    max_batch_bytes: profile.max_batch_bytes,
    representation: None,
    settled: false,
    closed: false,
    released: false,
  })
}

///|
fn native_strategy_local_input_source(
  owner : NativeStrategyLocalOwner,
  input : @execution.ProducerRead,
) -> NativeComputeRetainedInput? {
  guard owner.representation is Some(representation) &&
    @execution.producer_read_retained_material(input) is Some(material) &&
    physical_equal(representation.material, material) &&
    (representation.readable)(input) else {
    return None
  }
  Some({
    file: owner.file,
    wire: owner.wire,
    max_batch_bytes: owner.max_batch_bytes,
  })
}

///|
fn native_strategy_local_result_source(
  owner : NativeStrategyLocalOwner,
  output : @execution.CompletedOutput,
) -> NativeComputeRetainedInput? {
  guard owner.representation is Some(representation) &&
    @execution.retained_completed_material_matches(
      representation.material,
      output,
    ) else {
    return None
  }
  Some({
    file: owner.file,
    wire: owner.wire,
    max_batch_bytes: owner.max_batch_bytes,
  })
}

///|
fn import_native_strategy_local_input(
  transfer : @local_driver.LocalInputTransfer,
  source : NativeComputeRetainedInput,
) -> Result[Unit, NativeStrategyLocalIssue] {
  let limits = transfer.frames
  if source.max_batch_bytes < 1 ||
    limits.maxFrameBytes < 1 ||
    source.wire.max_bytes > limits.maxBytes ||
    source.file.stored_bytes() is None {
    return Err(InvalidState)
  }
  let frame_bytes = Int::min(
    65536,
    Int::min(source.max_batch_bytes, limits.maxFrameBytes),
  )
  let frames = match
    @publication.prepare_durable_result_row_frames(
      limits.maxBytes,
      limits.maxRows,
      limits.maxRowBytes,
      limits.maxDepth,
      frame_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativeStrategyLocalIssue::RowFrames(issue))
  }
  match (transfer.begin)() {
    Err(_) => return Err(InvalidState)
    Ok(_) => ()
  }
  let reader = match source.file.open_reader() {
    Ok(value) => value
    Err(issue) => return Err(NativeStrategyLocalIssue::RetainedFile(issue))
  }
  let mut eof = false
  while !eof {
    let chunk = match reader.next(frame_bytes) {
      Ok(value) => value
      Err(issue) => {
        reader.close() |> ignore
        return Err(NativeStrategyLocalIssue::RetainedFile(issue))
      }
    }
    match (transfer.charge)(chunk.bytes.length().to_int64()) {
      Ok(_) => ()
      Err(_) => {
        reader.close() |> ignore
        return Err(InvalidState)
      }
    }
    let rows = match
      @publication.feed_durable_result_row_frames(frames, chunk.bytes) {
      Ok(value) => value
      Err(issue) => {
        reader.close() |> ignore
        return Err(NativeStrategyLocalIssue::RowFrames(issue))
      }
    }
    for row in rows {
      match (transfer.append)(row) {
        Ok(_) => ()
        Err(_) => {
          reader.close() |> ignore
          return Err(InvalidState)
        }
      }
    }
    eof = chunk.eof
  }
  match @publication.finish_durable_result_row_frames(frames) {
    Ok(_) => ()
    Err(issue) => {
      reader.close() |> ignore
      return Err(NativeStrategyLocalIssue::RowFrames(issue))
    }
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => {
      reader.close() |> ignore
      return Err(NativeStrategyLocalIssue::RetainedFile(issue))
    }
  }
  (transfer.finish)().map_err(_ => InvalidState)
}

///|
fn execute_native_strategy_local_owner(
  owner : NativeStrategyLocalOwner,
  resolve : (@execution.ProducerRead) -> NativeComputeRetainedInput?,
) -> Result[Unit, NativeStrategyLocalIssue] {
  guard owner.operations.output is Some(output) else {
    return Err(MissingOutput)
  }
  match (output.install)(() => owner.file.release_confirmed()) {
    Ok(_) => ()
    Err(_) => return Err(InvalidState)
  }
  for input in owner.operations.inputs {
    guard resolve(input.input) is Some(source) else { return Err(InvalidState) }
    match import_native_strategy_local_input(input, source) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match (owner.operations.execute)() {
    Ok(_) => ()
    Err(_) => return Err(InvalidState)
  }
  match (output.begin)() {
    Ok(_) => ()
    Err(_) => return Err(InvalidState)
  }
  while true {
    match (output.next)() {
      Ok(Some(chunk)) =>
        match owner.file.append(chunk) {
          Ok(_) => ()
          Err(issue) =>
            return Err(NativeStrategyLocalIssue::RetainedFile(issue))
        }
      Ok(None) => break
      Err(_) => return Err(InvalidState)
    }
  }
  let content = match (output.finish)() {
    Ok(value) => value
    Err(_) => return Err(InvalidState)
  }
  match owner.file.append(content.tail) {
    Ok(_) => ()
    Err(issue) => return Err(NativeStrategyLocalIssue::RetainedFile(issue))
  }
  match owner.file.seal(content.cid, content.bytes) {
    Ok(_) => ()
    Err(issue) => return Err(NativeStrategyLocalIssue::RetainedFile(issue))
  }
  owner.representation = Some(
    match (content.bind)(() => owner.file.available()) {
      Ok(value) => value
      Err(_) => return Err(InvalidState)
    },
  )
  match (owner.operations.settle)() {
    Ok(_) => owner.settled = true
    Err(_) => return Err(InvalidState)
  }
  (owner.operations.complete)().map_err(_ => InvalidState)
}

///|
fn close_native_strategy_local_owner(
  owner : NativeStrategyLocalOwner,
) -> Result[Bool, NativeStrategyComputeCleanupIssue] {
  owner.file.stop_use()
  if !owner.settled {
    match (owner.operations.settle)() {
      Ok(_) => owner.settled = true
      Err(_) => return Err(LocalCleanup)
    }
  }
  if !owner.closed {
    (owner.operations.close)()
    owner.closed = true
  }
  match owner.file.reclaim_readers() {
    Ok(_) => ()
    Err(issue) => return Err(FileRelease(issue))
  }
  if !owner.released {
    match owner.file.release() {
      Ok(_) => ()
      Err(issue) => return Err(FileRelease(issue))
    }
    owner.released = true
  }
  match owner.operations.output {
    Some(output) => (output.refresh)().map_err(_ => LocalCleanup)
    None => Err(LocalCleanup)
  }
}
