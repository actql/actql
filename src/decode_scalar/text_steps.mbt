///|
/// Resumable form of raw UTF-8 measurement. Text is borrowed until completion;
/// identifier normalization is deliberately not part of this data-value scan.
struct Utf8Admission {
  mut text : String?
  limit : Int64
  mut offset : Int
  mut bytes : Int64
}

///|
pub enum Utf8AdmissionPoll {
  Utf8AdmissionContinue
  Utf8AdmissionComplete(Int64)
  Utf8AdmissionFailed(Utf8AdmissionIssue)
  Utf8AdmissionTerminal
}

///|
pub fn start_utf8_admission(
  text : String,
  limit : Int64,
) -> Result[Utf8Admission, Utf8AdmissionIssue] {
  if limit < 0 {
    return Err(InvalidLimit)
  }
  // Preserve the whole-input lower-bound precedence of the synchronous API.
  if text.length().to_int64() > limit {
    return Err(LimitExceeded)
  }
  Ok({ text: Some(text), limit, offset: 0, bytes: 0L, })
}

///|
pub fn Utf8Admission::advance(self : Utf8Admission) -> Utf8AdmissionPoll {
  guard self.text is Some(text) else { return Utf8AdmissionTerminal }
  let length = text.length()
  for _ in 0..<64 {
    if self.offset == length {
      self.text = None
      return Utf8AdmissionComplete(self.bytes)
    }
    // ASCII consumes one scalar and one byte without allocating an extent
    // tuple and Result. Keep the same quantum and first-overflow boundary.
    if text[self.offset].to_int() < 0x80 {
      if self.bytes == self.limit {
        self.cancel()
        return Utf8AdmissionFailed(LimitExceeded)
      }
      self.offset += 1
      self.bytes += 1L
      continue
    }
    let (next, width) = match utf8_scalar_extent(text, self.offset) {
      Ok(extent) => extent
      Err(issue) => {
        self.cancel()
        return Utf8AdmissionFailed(issue)
      }
    }
    if width.to_int64() > self.limit - self.bytes {
      self.cancel()
      return Utf8AdmissionFailed(LimitExceeded)
    }
    self.offset = next
    self.bytes += width.to_int64()
  }
  Utf8AdmissionContinue
}

///|
pub fn Utf8Admission::cancel(self : Utf8Admission) -> Unit {
  self.text = None
}

///|
/// One shared scalar rule for both synchronous and resumable byte admission.
fn utf8_scalar_extent(
  text : String,
  index : Int,
) -> Result[(Int, Int), Utf8AdmissionIssue] {
  let unit = text[index].to_int()
  if unit < 0x80 {
    Ok((index + 1, 1))
  } else if unit < 0x800 {
    Ok((index + 1, 2))
  } else if unit >= 0xd800 && unit <= 0xdbff {
    if index + 1 >= text.length() {
      return Err(MalformedUtf16(index))
    }
    let trailing = text[index + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      return Err(MalformedUtf16(index))
    }
    Ok((index + 2, 4))
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    Err(MalformedUtf16(index))
  } else {
    Ok((index + 1, 3))
  }
}
