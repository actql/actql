///|
/// Exact octets with one immutable, canonical wire backing. Only the Value
/// owner can construct this handle. Base64 is the encoding, not a Text value.
pub struct BinaryValue {
  wire : String
}

///|
fn base64_digit(code : Int) -> Int {
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 71
  } else if code >= 48 && code <= 57 {
    code + 4
  } else if code == 43 {
    62
  } else if code == 47 {
    63
  } else {
    -1
  }
}

///|
// A complete quad is always present. Padding belongs only at the end and
// unused low bits must be zero, so distinct wire Strings never alias a value.
fn binary_quad_valid(wire : String, offset : Int) -> Bool {
  let a = base64_digit(wire[offset].to_int())
  let b = base64_digit(wire[offset + 1].to_int())
  if a < 0 || b < 0 {
    return false
  }
  let c = base64_digit(wire[offset + 2].to_int())
  let d = base64_digit(wire[offset + 3].to_int())
  if c >= 0 && d >= 0 {
    return true
  }
  if offset + 4 != wire.length() || wire[offset + 3].to_int() != 61 {
    return false
  }
  if wire[offset + 2].to_int() == 61 {
    (b & 15) == 0
  } else {
    c >= 0 && (c & 3) == 0
  }
}

///|
/// Construct BYTES from an original immutable byte sequence. Fund the whole
/// canonical representation before the encoder allocates it.
pub fn bytes_value(bytes : Bytes, max_wire_bytes : Int) -> Value? {
  let size = (bytes.length().to_int64() + 2L) / 3L * 4L
  guard size <= max_wire_bytes.to_int64() else { return None }
  Some(Binary({ wire: encode_canonical_base64(bytes), }))
}

///|
/// Encode a checked Bytes view in standard, padded, canonical Base64.
/// The caller owns the representation budget for the input extent.
pub fn encode_canonical_base64(bytes : BytesView) -> String {
  @base64.encode(bytes)
}

///|
/// Decode canonical padded Base64 within the caller's checked byte limit.
pub fn decode_canonical_base64(wire : StringView, max_bytes : Int) -> Bytes? {
  let size = wire.length()
  guard max_bytes >= 0 &&
    size % 4 == 0 &&
    size.to_int64() <= (max_bytes.to_int64() + 2L) / 3L * 4L else {
    return None
  }
  let bytes = @base64.decode(wire) catch { _ => return None }
  guard bytes.length() <= max_bytes && encode_canonical_base64(bytes)[:] == wire else {
    return None
  }
  Some(bytes)
}

///|
/// Borrow the complete canonical wire in the original BYTES domain.
pub fn bytes_wire_text(value : BinaryValue) -> String {
  value.wire
}

///|
/// The number of original bytes, excluding the wire padding.
pub fn bytes_count(value : BinaryValue) -> Int {
  let size = value.wire.length()
  if size == 0 {
    return 0
  }
  let full = size / 4 * 3
  if value.wire[size - 2].to_int() == 61 {
    full - 2
  } else if value.wire[size - 1].to_int() == 61 {
    full - 1
  } else {
    full
  }
}

///|
/// Observe one original byte without copying or decoding the whole value.
pub fn bytes_at(value : BinaryValue, index : Int) -> Byte? {
  if index < 0 || index >= bytes_count(value) {
    return None
  }
  let digits = value.wire
  let first = index / 3 * 4 + index % 3
  let closed = base64_digit(digits[first].to_int())
  let open = base64_digit(digits[first + 1].to_int())
  let shift = 2 + index % 3 * 2
  Some(((closed << shift) | (open >> (6 - shift))).to_byte())
}
