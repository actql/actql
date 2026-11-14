///|
/// Portable framing for the canonical ordered-row payload. This parser owns
/// structure and limit decisions; adapters only supply bounded byte chunks.
struct DurableResultRowFrames {
  max_bytes : Int
  max_rows : Int
  max_row_bytes : Int
  max_depth : Int
  max_frame_bytes : Int
  mut row : Array[Byte]
  stack : Array[Byte]
  mut state : Int
  mut bytes : Int
  mut rows : Int
  mut size : Int
  mut depth : Int
  mut quoted : Bool
  mut escaped : Bool
  mut closed : Bool
}

///|
pub(all) enum DurableResultRowFrameIssue {
  DurableRowFrameInvalidLimits
  DurableRowFrameClosed
  DurableRowFrameByteLimit
  DurableRowFrameInvalidArray
  DurableRowFrameTrailingContent
  DurableRowFrameInvalidSeparator
  DurableRowFrameInvalidObject
  DurableRowFrameRowLimit
  DurableRowFrameRowSizeLimit
  DurableRowFrameDepthLimit
  DurableRowFrameInvalidNesting
  DurableRowFrameInvalidUtf8
  DurableRowFrameIncomplete
} derive(Eq, Debug)

///|
pub(all) struct DurableResultRowFrameSummary {
  bytes : Int
  rows : Int
} derive(Eq, Debug)

///|
pub fn prepare_durable_result_row_frames(
  max_bytes : Int,
  max_rows : Int,
  max_row_bytes : Int,
  max_depth : Int,
  max_frame_bytes : Int,
) -> Result[DurableResultRowFrames, DurableResultRowFrameIssue] {
  if max_bytes < 0 ||
    max_rows < 0 ||
    max_row_bytes < 1 ||
    max_depth < 1 ||
    max_depth > 64 ||
    max_frame_bytes < 1 {
    return Err(DurableRowFrameInvalidLimits)
  }
  Ok({
    max_bytes,
    max_rows,
    max_row_bytes,
    max_depth,
    max_frame_bytes,
    // The existing total-byte guard bounds every row byte as well. Retain the
    // original row limit; only unused private backing is reduced here. The
    // caller funds this same total-bounded backing before this constructor.
    // Physical chunk limits remain independent of the logical row bound.
    row: Array::make(Int::min(max_row_bytes, max_bytes), 0x00),
    stack: Array::make(max_depth, 0x00),
    state: 0,
    bytes: 0,
    rows: 0,
    size: 0,
    depth: 0,
    quoted: false,
    escaped: false,
    closed: false,
  })
}

///|
/// The installed READ owner reserves only this initial backing. Its original
/// Resource grow must complete before grow_durable_result_row_frame_buffer.
pub fn prepare_growing_durable_result_row_frames(
  max_bytes : Int,
  max_rows : Int,
  max_row_bytes : Int,
  max_depth : Int,
  max_frame_bytes : Int,
) -> Result[DurableResultRowFrames, DurableResultRowFrameIssue] {
  let frames = match
    prepare_durable_result_row_frames(
      Int::min(max_bytes, 32),
      max_rows,
      Int::min(max_row_bytes, 32),
      max_depth,
      max_frame_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..frames, max_bytes, max_row_bytes, })
}

///|
/// Pure upper bound from the SAME partial row and actual next chunk extent;
/// no second wire scan, row parsing, allocation or capacity issuance.
pub fn durable_result_row_frame_growth(
  frames : DurableResultRowFrames,
  chunk_bytes : Int,
) -> Result[Int, DurableResultRowFrameIssue] {
  if frames.closed {
    return Err(DurableRowFrameClosed)
  }
  if chunk_bytes < 0 ||
    chunk_bytes > frames.max_frame_bytes ||
    chunk_bytes > frames.max_bytes - frames.bytes {
    return Err(DurableRowFrameByteLimit)
  }
  let maximum = Int::min(frames.max_row_bytes, frames.max_bytes)
  let needed = if chunk_bytes > maximum - frames.size {
    maximum
  } else {
    frames.size + chunk_bytes
  }
  if needed <= frames.row.length() {
    return Ok(frames.row.length())
  }
  let doubled = if frames.row.length() > maximum / 2 {
    maximum
  } else {
    Int::min(maximum, Int::max(32, frames.row.length() * 2))
  }
  Ok(Int::max(needed, doubled))
}

///|
/// The caller's SAME READ parent must have admitted the old/new buffer peak
/// before this constructor; this typed framing operation grants no resources.
pub fn grow_durable_result_row_frame_buffer(
  frames : DurableResultRowFrames,
  bytes : Int,
) -> Result[Unit, DurableResultRowFrameIssue] {
  if frames.closed {
    return Err(DurableRowFrameClosed)
  }
  if bytes < frames.row.length() ||
    bytes > frames.max_row_bytes ||
    bytes > frames.max_bytes {
    return Err(DurableRowFrameInvalidLimits)
  }
  if bytes == frames.row.length() {
    return Ok(())
  }
  let original = frames.row
  let next = Array::makei(bytes, index => {
    if index < frames.size {
      original[index]
    } else {
      0x00
    }
  })
  frames.row = next
  Ok(())
}

///|
fn durable_row_frame_fail(
  frames : DurableResultRowFrames,
  issue : DurableResultRowFrameIssue,
) -> Result[Array[String], DurableResultRowFrameIssue] {
  frames.closed = true
  Err(issue)
}

///|
fn durable_row_frame_text(
  frames : DurableResultRowFrames,
) -> Result[String, DurableResultRowFrameIssue] {
  let bytes = Bytes::from_array(
    Array::makei(frames.size, index => frames.row[index]),
  )
  Ok(@utf8.decode(bytes)) catch {
    _ => Err(DurableRowFrameInvalidUtf8)
  }
}

///|
/// Consumes one physical chunk and returns the complete canonical row frames
/// found in that chunk. The returned collection is bounded by both the input
/// chunk and the admitted row count; incomplete rows remain in parser state.
pub fn feed_durable_result_row_frames(
  frames : DurableResultRowFrames,
  chunk : Bytes,
) -> Result[Array[String], DurableResultRowFrameIssue] {
  if frames.closed {
    return Err(DurableRowFrameClosed)
  }
  if chunk.length() > frames.max_frame_bytes ||
    chunk.length() > frames.max_bytes - frames.bytes {
    return durable_row_frame_fail(frames, DurableRowFrameByteLimit)
  }
  frames.bytes += chunk.length()
  let completed : Array[String] = []
  for byte in chunk {
    if frames.state == 0 {
      if byte != 0x5B {
        return durable_row_frame_fail(frames, DurableRowFrameInvalidArray)
      }
      frames.state = 1
      continue
    }
    if frames.state == 5 {
      return durable_row_frame_fail(frames, DurableRowFrameTrailingContent)
    }
    if frames.state == 3 {
      if byte == 0x5D {
        frames.state = 5
        continue
      }
      if byte != 0x2C {
        return durable_row_frame_fail(frames, DurableRowFrameInvalidSeparator)
      }
      frames.state = 4
      continue
    }
    if frames.state == 1 && byte == 0x5D {
      frames.state = 5
      continue
    }
    if frames.state == 1 || frames.state == 4 {
      if byte != 0x7B {
        return durable_row_frame_fail(frames, DurableRowFrameInvalidObject)
      }
      if frames.rows == frames.max_rows {
        return durable_row_frame_fail(frames, DurableRowFrameRowLimit)
      }
      frames.state = 2
      frames.size = 0
      frames.depth = 0
      frames.quoted = false
      frames.escaped = false
    }
    if frames.size == frames.max_row_bytes {
      return durable_row_frame_fail(frames, DurableRowFrameRowSizeLimit)
    }
    if frames.size == frames.row.length() {
      return durable_row_frame_fail(frames, DurableRowFrameRowSizeLimit)
    }
    frames.row[frames.size] = byte
    frames.size += 1
    if frames.quoted {
      if frames.escaped {
        frames.escaped = false
      } else if byte == 0x5C {
        frames.escaped = true
      } else if byte == 0x22 {
        frames.quoted = false
      }
      continue
    }
    if byte == 0x22 {
      frames.quoted = true
      continue
    }
    if byte == 0x7B || byte == 0x5B {
      if frames.depth == frames.max_depth {
        return durable_row_frame_fail(frames, DurableRowFrameDepthLimit)
      }
      frames.stack[frames.depth] = byte
      frames.depth += 1
    } else if byte == 0x7D || byte == 0x5D {
      let expected : Byte = if byte == 0x7D { 0x7B } else { 0x5B }
      if frames.depth == 0 || frames.stack[frames.depth - 1] != expected {
        return durable_row_frame_fail(frames, DurableRowFrameInvalidNesting)
      }
      frames.depth -= 1
      if frames.depth == 0 {
        let text = match durable_row_frame_text(frames) {
          Ok(value) => value
          Err(issue) => return durable_row_frame_fail(frames, issue)
        }
        completed.push(text)
        frames.rows += 1
        frames.state = 3
        frames.size = 0
      }
    }
  }
  Ok(completed)
}

///|
pub fn finish_durable_result_row_frames(
  frames : DurableResultRowFrames,
) -> Result[DurableResultRowFrameSummary, DurableResultRowFrameIssue] {
  if frames.closed {
    return Err(DurableRowFrameClosed)
  }
  frames.closed = true
  if frames.state != 5 {
    return Err(DurableRowFrameIncomplete)
  }
  Ok({ bytes: frames.bytes, rows: frames.rows, })
}

///|
pub fn cancel_durable_result_row_frames(
  frames : DurableResultRowFrames,
) -> Unit {
  frames.closed = true
}
