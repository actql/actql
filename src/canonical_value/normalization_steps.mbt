///|
/// Cooperative Unicode 16 normalization. Every advance performs at most one
/// input decode, bounded table expansion, ordering swap, or composition.
/// The caller reserves 18 scalar slots per input UTF-16 unit before construction.
pub struct NormalizationCursor {
  input : String
  fold : Bool
  mut offset : Int
  values : Array[Int]
  mut pending : Array[Int]
  mut next : Int
  mut ordering : Int
  mut phase : Int
  mut read : Int
  mut written : Int
  mut starter : Int
  mut previous_class : Int
}

///|
pub fn start_normalization(input : String, fold : Bool) -> NormalizationCursor {
  {
    input,
    fold,
    offset: 0,
    values: [],
    pending: [],
    next: 0,
    ordering: -1,
    phase: 0,
    read: 0,
    written: 0,
    starter: 0,
    previous_class: 0,
  }
}

///|
fn normalization_mapping(cp : Int, fold : Bool) -> Array[Int] {
  // Hangul NFD is algorithmic, including when no case-fold mapping exists.
  if cp >= 0xac00 && cp < 0xd7a4 {
    let s = cp - 0xac00
    let out = [0x1100 + s / 588, 0x1161 + s % 588 / 28]
    if s % 28 != 0 {
      out.push(0x11a7 + s % 28)
    }
    return out
  }
  let keys = if fold { folding_keys } else { compatibility_keys }
  let offsets = if fold { folding_offsets } else { compatibility_offsets }
  let data = if fold { folding_data } else { compatibility_data }
  match lookup_int(keys, cp) {
    None => [cp]
    Some(index) => {
      let out = []
      for i in offsets[index]..<offsets[index + 1] {
        out.push(data[i])
      }
      out
    }
  }
}

///|
pub fn advance_normalization(
  cursor : NormalizationCursor,
) -> Result[Bool, TextNormalizationError] {
  if cursor.phase == 2 {
    return Ok(true)
  }
  if cursor.phase == 0 {
    if cursor.ordering > 0 {
      let i = cursor.ordering
      let a = canonical_combining_class(cursor.values[i - 1])
      let b = canonical_combining_class(cursor.values[i])
      if b != 0 && a > b {
        let temp = cursor.values[i]
        cursor.values[i] = cursor.values[i - 1]
        cursor.values[i - 1] = temp
        cursor.ordering -= 1
      } else {
        cursor.ordering = -1
      }
      return Ok(false)
    }
    if cursor.next < cursor.pending.length() {
      cursor.values.push(cursor.pending[cursor.next])
      cursor.next += 1
      cursor.ordering = cursor.values.length() - 1
      return Ok(false)
    }
    if cursor.offset == cursor.input.length() {
      cursor.pending = []
      cursor.phase = 1
      return Ok(false)
    }
    let at = cursor.offset
    let unit = cursor.input[at].to_int()
    let cp = if unit >= 0xd800 && unit <= 0xdbff {
      if at + 1 >= cursor.input.length() {
        return Err(UnpairedSurrogate(at))
      }
      let low = cursor.input[at + 1].to_int()
      if low < 0xdc00 || low > 0xdfff {
        return Err(UnpairedSurrogate(at))
      }
      cursor.offset += 2
      0x10000 + ((unit - 0xd800) << 10) + low - 0xdc00
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return Err(UnpairedSurrogate(at))
    } else {
      cursor.offset += 1
      unit
    }
    cursor.pending = normalization_mapping(cp, cursor.fold)
    cursor.next = 0
    return Ok(false)
  }
  if cursor.read == cursor.values.length() {
    cursor.phase = 2
    return Ok(true)
  }
  let cp = cursor.values[cursor.read]
  let cls = canonical_combining_class(cp)
  cursor.read += 1
  if cursor.written == 0 {
    cursor.values[0] = cp
    cursor.written = 1
    cursor.starter = 0
    cursor.previous_class = cls
    return Ok(false)
  }
  let composite = canonical_composition(cursor.values[cursor.starter], cp)
  if composite is Some(value) &&
    (cursor.previous_class == 0 || cursor.previous_class < cls) {
    cursor.values[cursor.starter] = value
  } else {
    if cls == 0 {
      cursor.starter = cursor.written
    }
    cursor.values[cursor.written] = cp
    cursor.written += 1
    cursor.previous_class = cls
  }
  Ok(false)
}

///|
pub fn normalization_count(cursor : NormalizationCursor) -> Int {
  if cursor.phase == 2 {
    cursor.written
  } else {
    0
  }
}

///|
pub fn normalization_scalar(cursor : NormalizationCursor, index : Int) -> Char? {
  if cursor.phase != 2 || index < 0 || index >= cursor.written {
    None
  } else {
    Some(cursor.values[index].unsafe_to_char())
  }
}
