///|
/// Physical custody remains attached until both file cleanup and the original
/// Run owner confirm cleanup. Neither step returns capacity by itself.
fn retain_standard_output_cleanup(
  file : @retained_file.NativeRetainedTaskFile?,
  release_run : () -> Bool,
) -> () -> Bool {
  () => {
    if file is Some(file) {
      file.stop_use()
      if file.reclaim_readers() is Err(_) || file.release() is Err(_) {
        return false
      }
    }
    release_run()
  }
}

///|
fn open_retained_standard_reader(
  file : @retained_file.NativeRetainedTaskFile,
) -> Result[@runtime.NativeRemotePhysicalReader, String] {
  let reader = match file.open_reader() {
    Ok(value) => value
    Err(_) => return Err("output-retained-open")
  }
  Ok(
    @runtime.prepare_native_remote_physical_reader(
      max_bytes => {
        reader
        .next(max_bytes)
        .map(chunk => {
          (
            { bytes: chunk.bytes, eof: chunk.eof, } :
            @runtime.NativeRemoteOutputChunk)
        })
        .map_err(_ => "output-retained-read")
      },
      () => reader.finish().map_err(_ => "output-retained-finish"),
      () => reader.close().map_err(_ => "output-retained-close"),
    ),
  )
}

///|
priv struct NativeRemoteStandardRetainedManifestReader {
  reader : @retained_file.NativeRetainedTaskReader
  lengths : Array[Int64]
  mut next_index : Int
  mut closed : Bool
}

///|
fn NativeRemoteStandardRetainedManifestReader::next(
  self : NativeRemoteStandardRetainedManifestReader,
  index : Int,
) -> Result[Bytes, String] {
  if self.closed || index != self.next_index || index >= self.lengths.length() {
    return Err("invalid-manifest-reader-state")
  }
  let length = self.lengths[index]
  if length < 1L || length > 1048576L {
    return Err("output-manifest-chunk")
  }
  let bytes : Array[Byte] = Array::make(length.to_int(), b'\x00')
  let mut offset = 0
  while offset < bytes.length() {
    let chunk = match self.reader.next(bytes.length() - offset) {
      Ok(value) => value
      Err(_) => return Err("output-retained-read")
    }
    if chunk.eof ||
      chunk.bytes.length() == 0 ||
      chunk.bytes.length() > bytes.length() - offset {
      return Err("output-retained-truncated")
    }
    for byte in chunk.bytes {
      bytes[offset] = byte
      offset += 1
    }
  }
  self.next_index += 1
  Ok(Bytes::from_array(bytes))
}

///|
fn NativeRemoteStandardRetainedManifestReader::finish(
  self : NativeRemoteStandardRetainedManifestReader,
) -> Result[Unit, String] {
  if self.closed {
    return Ok(())
  }
  if self.next_index != self.lengths.length() {
    return Err("output-manifest-reader-incomplete")
  }
  // Verify both exact manifest coverage and the complete original stream CID.
  let tail = match self.reader.next(1) {
    Ok(value) => value
    Err(_) => return Err("output-retained-read")
  }
  if !tail.eof || tail.bytes.length() != 0 {
    return Err("output-retained-extent")
  }
  match self.reader.finish() {
    Err(_) => Err("output-retained-finish")
    Ok(_) => {
      self.closed = true
      Ok(())
    }
  }
}

///|
fn NativeRemoteStandardRetainedManifestReader::close(
  self : NativeRemoteStandardRetainedManifestReader,
) -> Result[Unit, String] {
  if self.closed {
    return Ok(())
  }
  match self.reader.close() {
    Err(_) => Err("output-retained-close")
    Ok(_) => {
      self.closed = true
      Ok(())
    }
  }
}

///|
fn open_retained_standard_manifest_reader(
  file : @retained_file.NativeRetainedTaskFile,
  lengths : Array[Int64],
) -> Result[@runtime.NativeRemotePhysicalManifestReader, String] {
  let reader = match file.open_reader() {
    Ok(value) => value
    Err(_) => return Err("output-retained-open")
  }
  let state : NativeRemoteStandardRetainedManifestReader = {
    reader,
    lengths: lengths.copy(),
    next_index: 0,
    closed: false,
  }
  Ok(
    @runtime.prepare_native_remote_physical_manifest_reader(
      index => state.next(index),
      () => state.finish(),
      () => state.close(),
    ),
  )
}
