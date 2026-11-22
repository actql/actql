// Copyright (c) 2014 Google, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// Streaming port of the stable farmhashna Fingerprint64 kernel from
// google/farmhash at 0d859a811870d10f53a594927d0d0b97573ad06d.

///|
const FARM_K0 : UInt64 = 0xc3a5c85c97cb3127UL

///|
const FARM_K1 : UInt64 = 0xb492b66fbe98f273UL

///|
const FARM_K2 : UInt64 = 0x9ae16a3b2f90404fUL

///|
// Continuation (two entries), state (thirteen), ring (nine), and six
// overlapping weak-hash pair entries. The input is the original Text root.
const FARM_FINGERPRINT_SLOTS : Int = 30

///|
priv struct FarmFingerprint {
  expression : @lower.Expression
  text : String
  ring : FixedArray[UInt64]
  mut position : Int
  mut bytes : Int64
  mut x : UInt64
  mut y : UInt64
  mut z : UInt64
  mut v0 : UInt64
  mut v1 : UInt64
  mut w0 : UInt64
  mut w1 : UInt64
}

///|
fn farm_rotate(n : UInt64, count : Int) -> UInt64 {
  (n >> count) | (n << (64 - count))
}

///|
fn farm_shift_mix(n : UInt64) -> UInt64 {
  n ^ (n >> 47)
}

///|
fn farm_mix_pair(a : UInt64, b : UInt64, factor : UInt64) -> UInt64 {
  farm_shift_mix((b ^ farm_shift_mix((a ^ b) * factor)) * factor) * factor
}

///|
fn farm_word(state : FarmFingerprint, offset : Int) -> UInt64 {
  let lane = (offset & 63) >> 3
  let shift = (offset & 7) << 3
  let low = state.ring[lane] >> shift
  if shift == 0 {
    low
  } else {
    low | (state.ring[(lane + 1) & 7] << (64 - shift))
  }
}

///|
fn farm_short(state : FarmFingerprint, count : Int) -> UInt64 {
  if count == 0 {
    return FARM_K2
  }
  let length = count.to_uint64()
  if count < 4 {
    let first = farm_word(state, 0) & 255UL
    let middle = farm_word(state, count >> 1) & 255UL
    let last = farm_word(state, count - 1) & 255UL
    return farm_shift_mix(
        ((first + (middle << 8)) * FARM_K2) ^ ((length + (last << 2)) * FARM_K0),
      ) *
      FARM_K2
  }
  let factor = FARM_K2 + length * 2UL
  if count < 8 {
    let first = farm_word(state, 0) & 0xffffffffUL
    let last = farm_word(state, count - 4) & 0xffffffffUL
    return farm_mix_pair(length + (first << 3), last, factor)
  }
  if count <= 16 {
    let first = farm_word(state, 0) + FARM_K2
    let last = farm_word(state, count - 8)
    return farm_mix_pair(
      farm_rotate(last, 37) * factor + first,
      (farm_rotate(first, 25) + last) * factor,
      factor,
    )
  }
  let first = farm_word(state, 0) *
    (if count <= 32 { FARM_K1 } else { FARM_K2 })
  let second = farm_word(state, 8)
  let last = farm_word(state, count - 8) * factor
  let penultimate = farm_word(state, count - 16) * FARM_K2
  let left = farm_rotate(first + second, 43) +
    farm_rotate(last, 30) +
    penultimate
  let right = first + farm_rotate(second + FARM_K2, 18) + last
  if count <= 32 {
    return farm_mix_pair(left, right, factor)
  }
  let mid_left = farm_word(state, 16) * factor
  let mid_right = farm_word(state, 24)
  let tail_left = (left + farm_word(state, count - 32)) * factor
  let tail_right = (
      farm_mix_pair(left, right, factor) + farm_word(state, count - 24)
    ) *
    factor
  farm_mix_pair(
    farm_rotate(mid_left + mid_right, 43) +
    farm_rotate(tail_left, 30) +
    tail_right,
    mid_left + farm_rotate(mid_right + first, 18) + tail_left,
    factor,
  )
}

///|
fn farm_weak_hash(
  state : FarmFingerprint,
  offset : Int,
  seed_a : UInt64,
  seed_b : UInt64,
) -> (UInt64, UInt64) {
  let a = seed_a + farm_word(state, offset)
  let last = farm_word(state, offset + 24)
  let b = farm_rotate(seed_b + a + last, 21)
  let sum = a + farm_word(state, offset + 8) + farm_word(state, offset + 16)
  (sum + last, b + farm_rotate(sum, 44) + a)
}

///|
fn farm_block(
  state : FarmFingerprint,
  offset : Int,
  factor : UInt64,
  tail_scale : UInt64,
) -> Unit {
  let x = (
      farm_rotate(
        state.x + state.y + state.v0 + farm_word(state, offset + 8),
        37,
      ) *
      factor
    ) ^
    (state.w1 * tail_scale)
  let y = farm_rotate(state.y + state.v1 + farm_word(state, offset + 48), 42) *
    factor +
    state.v0 * tail_scale +
    farm_word(state, offset + 40)
  let z = farm_rotate(state.z + state.w0, 33) * factor
  let (v0, v1) = farm_weak_hash(state, offset, state.v1 * factor, x + state.w0)
  let (w0, w1) = farm_weak_hash(
    state,
    offset + 32,
    z + state.w1,
    y + farm_word(state, offset + 16),
  )
  state.v0 = v0
  state.v1 = v1
  state.w0 = w0
  state.w1 = w1
  state.x = z
  state.y = y
  state.z = x
}

///|
fn farm_push_byte(state : FarmFingerprint, byte : Int) -> Unit {
  let offset = (state.bytes & 63L).to_int()
  // A full block is processed only when another byte arrives. This leaves
  // exactly the reference's 1–64 unprocessed bytes at the end, and the ring
  // retains the possibly overlapping final 64 bytes without a second copy.
  if offset == 0 && state.bytes > 0L {
    if state.bytes == 64L {
      state.x = 81UL * FARM_K2 + farm_word(state, 0)
    }
    farm_block(state, 0, FARM_K1, 1UL)
  }
  let lane = offset >> 3
  let shift = (offset & 7) << 3
  state.ring[lane] = (state.ring[lane] & (255UL << shift).lnot()) |
    (byte.to_uint64() << shift)
  state.bytes += 1L
}

///|
fn farm_push_scalar(state : FarmFingerprint, scalar : Char) -> Unit {
  let point = scalar.to_int()
  if point < 0x80 {
    farm_push_byte(state, point)
    return
  }
  if point < 0x800 {
    farm_push_byte(state, 0xc0 | (point >> 6))
  } else {
    if point < 0x10000 {
      farm_push_byte(state, 0xe0 | (point >> 12))
    } else {
      farm_push_byte(state, 0xf0 | (point >> 18))
      farm_push_byte(state, 0x80 | ((point >> 12) & 63))
    }
    farm_push_byte(state, 0x80 | ((point >> 6) & 63))
  }
  farm_push_byte(state, 0x80 | (point & 63))
}

///|
fn start_farm_fingerprint(
  expression : @lower.Expression,
  text : String,
  workspace : RowWorkspace,
) -> Result[FarmFingerprint, EvalIssue] {
  if !reserve_slots(workspace, FARM_FINGERPRINT_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let y = 81UL * FARM_K1 + 113UL
  Ok({
    expression,
    text,
    ring: FixedArray::make(8, 0UL),
    position: 0,
    bytes: 0L,
    x: 0UL,
    y,
    z: farm_shift_mix(y * FARM_K2 + 113UL) * FARM_K2,
    v0: 0UL,
    v1: 0UL,
    w0: 0UL,
    w1: 0UL,
  })
}

///|
// A poll consumes one Unicode scalar (at most four bytes and one full block)
// or finalizes the fixed ring. Control work and cancellation stay in the
// existing expression loop.
fn advance_farm_fingerprint(
  state : FarmFingerprint,
) -> Result[Value?, EvalIssue] {
  if state.position < state.text.length() {
    guard text_function_scalar(state.text, state.position)
      is Some((scalar, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression: state.expression, })
    }
    farm_push_scalar(state, scalar)
    state.position = next
    return Ok(None)
  }
  let fingerprint = if state.bytes <= 64L {
    farm_short(state, state.bytes.to_int())
  } else {
    let factor = FARM_K1 + ((state.z & 255UL) << 1)
    state.w0 += ((state.bytes - 1L) & 63L).reinterpret_as_uint64()
    state.v0 += state.w0
    state.w0 += state.v0
    farm_block(state, (state.bytes & 63L).to_int(), factor, 9UL)
    farm_mix_pair(
      farm_mix_pair(state.v0, state.w0, factor) +
      farm_shift_mix(state.y) * FARM_K0 +
      state.z,
      farm_mix_pair(state.v1, state.w1, factor) + state.x,
      factor,
    )
  }
  Ok(
    Some(capture(@admitted.signed64_value(fingerprint.reinterpret_as_int64()))),
  )
}
