///|
/// Copy exactly one finite UTF-8 byte range. A range can start or end within
/// a scalar. The caller owns the original text and funds the requested copy.
pub fn copy_utf8_byte_range(text : String, offset : Int, size : Int) -> Bytes? {
  if offset < 0 || size <= 0 || offset > 2147483647 - size {
    return None
  }
  let end = offset + size
  let result : Array[Byte] = Array(capacity=size)
  let position = Ref(0)
  let write = (byte : Int) => {
    if position.val < end {
      if position.val >= offset {
        result.push(byte.to_byte())
      }
      position.val += 1
    }
  }
  for point in text.iter() {
    if position.val >= end {
      break
    }
    let code = point.to_int()
    if code < 0x80 {
      write(code)
    } else if code < 0x800 {
      write(0xc0 | (code >> 6))
      write(0x80 | (code & 63))
    } else if code < 0x10000 {
      write(0xe0 | (code >> 12))
      write(0x80 | ((code >> 6) & 63))
      write(0x80 | (code & 63))
    } else {
      write(0xf0 | (code >> 18))
      write(0x80 | ((code >> 12) & 63))
      write(0x80 | ((code >> 6) & 63))
      write(0x80 | (code & 63))
    }
  }
  if result.length() == size {
    Some(Bytes::from_array(result))
  } else {
    None
  }
}
