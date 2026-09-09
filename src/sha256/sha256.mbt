///|
let initial_state : FixedArray[UInt] = [
  0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU, 0x1f83d9abU,
  0x5be0cd19U,
]

///|
let round_constants : FixedArray[UInt] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
fn rotate_right(value : UInt, bits : Int) -> UInt {
  (value >> bits) | (value << (32 - bits))
}

///|
fn word_at(input : Array[Byte], offset : Int) -> UInt {
  (input[offset].to_uint() << 24) |
  (input[offset + 1].to_uint() << 16) |
  (input[offset + 2].to_uint() << 8) |
  input[offset + 3].to_uint()
}

///|
/// Returns the 32-byte SHA-256 digest without modifying the input.
pub fn digest(input : Bytes) -> Bytes {
  let bytes = input.to_array()
  let original_length = bytes.length()
  bytes.push(0x80)
  while bytes.length() % 64 != 56 {
    bytes.push(0x00)
  }
  let bit_length = UInt64::extend_uint(original_length.reinterpret_as_uint()) *
    8UL
  let length_bytes = bit_length.to_be_bytes()
  for byte in length_bytes {
    bytes.push(byte)
  }
  let state : Array[UInt] = initial_state.iter().collect()
  let words = Array::make(64, 0U)
  for offset = 0; offset < bytes.length(); offset = offset + 64 {
    for index = 0; index < 16; index = index + 1 {
      words[index] = word_at(bytes, offset + index * 4)
    }
    for index = 16; index < 64; index = index + 1 {
      let earlier = words[index - 15]
      let later = words[index - 2]
      let s0 = rotate_right(earlier, 7) ^
        rotate_right(earlier, 18) ^
        (earlier >> 3)
      let s1 = rotate_right(later, 17) ^ rotate_right(later, 19) ^ (later >> 10)
      words[index] = words[index - 16] + s0 + words[index - 7] + s1
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for index = 0; index < 64; index = index + 1 {
      let sigma1 = rotate_right(e, 6) ^
        rotate_right(e, 11) ^
        rotate_right(e, 25)
      let choose = (e & f) ^ (e.lnot() & g)
      let temp1 = h + sigma1 + choose + round_constants[index] + words[index]
      let sigma0 = rotate_right(a, 2) ^
        rotate_right(a, 13) ^
        rotate_right(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temp2 = sigma0 + majority
      h = g
      g = f
      f = e
      e = d + temp1
      d = c
      c = b
      b = a
      a = temp1 + temp2
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
    state[4] = state[4] + e
    state[5] = state[5] + f
    state[6] = state[6] + g
    state[7] = state[7] + h
  }
  let output : Array[Byte] = []
  for word in state {
    output.push((word >> 24).to_byte())
    output.push((word >> 16).to_byte())
    output.push((word >> 8).to_byte())
    output.push(word.to_byte())
  }
  Bytes::from_array(output)
}

///|
/// Returns the SHA-256 digest as 64 lowercase hexadecimal characters.
pub fn hex(input : Bytes) -> String {
  let builder = StringBuilder(size_hint=64)
  for byte in digest(input) {
    let part = byte.to_hex()
    if part.length() == 1 {
      builder.write_char('0')
    }
    builder.write_string(part)
  }
  builder.to_string()
}

///|
/// A text encoding failure at a zero-based UTF-16 code-unit offset.
pub(all) enum TextEncodingError {
  UnpairedSurrogate(Int)
} derive(Eq, Debug)

///|
/// Hashes the UTF-8 encoding without Unicode or newline normalization.
/// Input must represent Unicode scalar values. Unpaired surrogates are rejected
/// before encoding, rather than replaced or passed to a backend that may panic.
pub fn text_hex(input : String) -> Result[String, TextEncodingError] {
  let mut index = 0
  while index < input.length() {
    let unit = input[index].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if index + 1 >= input.length() {
        return Err(UnpairedSurrogate(index))
      }
      let low = input[index + 1].to_int()
      if low < 0xDC00 || low > 0xDFFF {
        return Err(UnpairedSurrogate(index))
      }
      index = index + 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      return Err(UnpairedSurrogate(index))
    } else {
      index = index + 1
    }
  }
  Ok(hex(@utf8.encode(input)))
}
