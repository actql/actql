///|
/// A normalization failure at a zero-based UTF-16 code-unit offset.
pub(all) enum TextNormalizationError {
  UnpairedSurrogate(Int)
} derive(Eq, Debug)

///|
fn lookup_int(keys : FixedArray[Int], needle : Int) -> Int? {
  let mut low = 0
  let mut high = keys.length()
  while low < high {
    let middle = low + (high - low) / 2
    let key = keys[middle]
    if key < needle {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low < keys.length() && keys[low] == needle {
    Some(low)
  } else {
    None
  }
}

///|
fn lookup_int64(keys : FixedArray[Int64], needle : Int64) -> Int? {
  let mut low = 0
  let mut high = keys.length()
  while low < high {
    let middle = low + (high - low) / 2
    let key = keys[middle]
    if key < needle {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low < keys.length() && keys[low] == needle {
    Some(low)
  } else {
    None
  }
}

///|
fn canonical_combining_class(codepoint : Int) -> Int {
  match lookup_int(canonical_combining_class_keys, codepoint) {
    Some(index) => canonical_combining_class_values[index]
    None => 0
  }
}

///|
fn append_canonical_decomposition(codepoint : Int, output : Array[Int]) -> Unit {
  // UAX #15 Hangul decomposition is algorithmic and is not listed in
  // UnicodeData.txt.
  let s_base = 0xAC00
  let l_base = 0x1100
  let v_base = 0x1161
  let t_base = 0x11A7
  let l_count = 19
  let v_count = 21
  let t_count = 28
  let n_count = v_count * t_count
  let s_count = l_count * n_count
  if codepoint >= s_base && codepoint < s_base + s_count {
    let s_index = codepoint - s_base
    output.push(l_base + s_index / n_count)
    output.push(v_base + s_index % n_count / t_count)
    let t_index = s_index % t_count
    if t_index != 0 {
      output.push(t_base + t_index)
    }
    return
  }
  match lookup_int(canonical_decomposition_keys, codepoint) {
    None => output.push(codepoint)
    Some(index) => {
      let start = canonical_decomposition_offsets[index]
      let limit = canonical_decomposition_offsets[index + 1]
      for offset = start; offset < limit; offset = offset + 1 {
        append_canonical_decomposition(
          canonical_decomposition_data[offset],
          output,
        )
      }
    }
  }
}

///|
fn order_canonically(values : Array[Int]) -> Unit {
  // CCC is an integer in 0..255. Stable counting sort bounds each nonstarter
  // run by O(length + 256), including reverse-ordered adversarial input.
  // Starters (CCC 0) never move; leading nonstarters form their own run.
  let classes = values.map(canonical_combining_class)
  let mut start = 0
  while start < values.length() {
    if classes[start] == 0 {
      start = start + 1
      continue
    }
    let mut end = start + 1
    let mut ordered = true
    while end < values.length() && classes[end] != 0 {
      if classes[end - 1] > classes[end] {
        ordered = false
      }
      end = end + 1
    }
    if !ordered {
      let offsets = Array::make(256, 0)
      for index = start; index < end; index = index + 1 {
        offsets[classes[index]] = offsets[classes[index]] + 1
      }
      let mut position = 0
      for combining = 1; combining < 256; combining = combining + 1 {
        let count = offsets[combining]
        offsets[combining] = position
        position = position + count
      }
      let sorted = Array::make(end - start, 0)
      for index = start; index < end; index = index + 1 {
        let combining = classes[index]
        sorted[offsets[combining]] = values[index]
        offsets[combining] = offsets[combining] + 1
      }
      for index = start; index < end; index = index + 1 {
        values[index] = sorted[index - start]
      }
    }
    start = end
  }
}

///|
fn hangul_composition(starter : Int, codepoint : Int) -> Int? {
  let s_base = 0xAC00
  let l_base = 0x1100
  let v_base = 0x1161
  let t_base = 0x11A7
  let l_count = 19
  let v_count = 21
  let t_count = 28
  let n_count = v_count * t_count
  let s_count = l_count * n_count
  if starter >= l_base &&
    starter < l_base + l_count &&
    codepoint >= v_base &&
    codepoint < v_base + v_count {
    return Some(
      s_base + (starter - l_base) * n_count + (codepoint - v_base) * t_count,
    )
  }
  if starter >= s_base &&
    starter < s_base + s_count &&
    (starter - s_base) % t_count == 0 &&
    codepoint > t_base &&
    codepoint < t_base + t_count {
    return Some(starter + codepoint - t_base)
  }
  None
}

///|
fn canonical_composition(starter : Int, codepoint : Int) -> Int? {
  match hangul_composition(starter, codepoint) {
    Some(value) => Some(value)
    None => {
      let key = (starter.to_int64() << 21) | codepoint.to_int64()
      match lookup_int64(canonical_composition_keys, key) {
        Some(index) => Some(canonical_composition_values[index])
        None => None
      }
    }
  }
}

///|
fn compose_nfc(ordered : Array[Int]) -> Array[Int] {
  if ordered.is_empty() {
    return []
  }
  let output : Array[Int] = [ordered[0]]
  let mut starter_position = 0
  let mut starter = ordered[0]
  let mut previous_combining = 0
  for index = 1; index < ordered.length(); index = index + 1 {
    let codepoint = ordered[index]
    let combining = canonical_combining_class(codepoint)
    let composite = canonical_composition(starter, codepoint)
    if composite is Some(value) &&
      (previous_combining == 0 || previous_combining < combining) {
      output[starter_position] = value
      starter = value
    } else {
      if combining == 0 {
        starter_position = output.length()
        starter = codepoint
      }
      output.push(codepoint)
      previous_combining = combining
    }
  }
  output
}

///|
fn scalar_values(value : String) -> Result[Array[Int], TextNormalizationError] {
  let output : Array[Int] = []
  let mut index = 0
  while index < value.length() {
    let unit = value[index].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if index + 1 >= value.length() {
        return Err(UnpairedSurrogate(index))
      }
      let low = value[index + 1].to_int()
      if low < 0xDC00 || low > 0xDFFF {
        return Err(UnpairedSurrogate(index))
      }
      output.push(0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00)
      index = index + 2
      continue
    }
    if unit >= 0xDC00 && unit <= 0xDFFF {
      return Err(UnpairedSurrogate(index))
    }
    output.push(unit)
    index = index + 1
  }
  Ok(output)
}

///|
/// Normalizes to Unicode 16.0 NFC, then folds CRLF and lone CR to LF.
/// Unpaired surrogates are rejected without replacement.
pub fn normalize_nfc_lf(
  value : String,
) -> Result[String, TextNormalizationError] {
  match normalize_nfc(value) {
    Err(error) => Err(error)
    Ok(normalized) =>
      Ok(
        normalized
        .replace_all(old="\r\n", new="\n")
        .replace_all(old="\r", new="\n"),
      )
  }
}

///|
/// Normalizes to Unicode 16.0 NFC without changing newlines.
/// Unpaired surrogates are rejected without replacement.
pub fn normalize_nfc(value : String) -> Result[String, TextNormalizationError] {
  normalize_text(value)
}

///|
fn normalize_text(value : String) -> Result[String, TextNormalizationError] {
  // ASCII is already NFC. Non-ASCII input always takes the validating path.
  let mut normalized_ascii = true
  for index = 0; index < value.length(); index = index + 1 {
    let unit = value[index].to_int()
    if unit > 0x7F {
      normalized_ascii = false
      break
    }
  }
  if normalized_ascii {
    return Ok(value)
  }
  match scalar_values(value) {
    Err(error) => Err(error)
    Ok(scalars) => {
      let decomposed : Array[Int] = []
      for scalar in scalars {
        append_canonical_decomposition(scalar, decomposed)
      }
      order_canonically(decomposed)
      let composed = compose_nfc(decomposed)
      let builder = StringBuilder(size_hint=value.length())
      for scalar in composed {
        builder.write_char(scalar.unsafe_to_char())
      }
      Ok(builder.to_string())
    }
  }
}

///|
/// Returns -1, 0 or 1 in raw UTF-16 code-unit order.
/// This does not validate or normalize either input. ActQL semantic ordering
/// requires callers to validate and NFC-normalize both strings first.
pub fn compare_utf16(left : String, right : String) -> Int {
  let common = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index = 0; index < common; index = index + 1 {
    let left_unit = left[index]
    let right_unit = right[index]
    if left_unit < right_unit {
      return -1
    }
    if left_unit > right_unit {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}
