///|
// Nominal owned buffer capacity, not GC/allocator bytes or process RSS.
// Container slots and typed element bytes deliberately remain separate units.
priv struct LayoutLedger {
  slots : RowWorkspace
  bytes : RowWorkspace
  work : ControlBudget
}

///|
priv struct LayoutBuffer {
  ledger : LayoutLedger
  slots : Int
  bytes : Int
  mut owners : Int
}

///|
priv struct LayoutBufferLease {
  buffer : LayoutBuffer
  mut released : Bool
}

///|
// A handle releases its actual strong reference together with its capacity.
// Merely decrementing a counter while retaining `value` would undercount memory.
priv struct LayoutOwnedBuffer[T] {
  lease : LayoutBufferLease
  mut value : T?
}

///|
fn[T] allocate_owned_layout_buffer(
  ledger : LayoutLedger,
  slots : Int,
  bytes : Int,
  build : () -> T,
) -> Result[LayoutOwnedBuffer[T], LayoutStorageIssue] {
  match allocate_layout_buffer(ledger, slots, bytes) {
    Err(issue) => Err(issue)
    Ok(lease) => Ok({ lease, value: Some(build()), })
  }
}

///|
fn[T] share_owned_layout_buffer(
  ledger : LayoutLedger,
  buffer : LayoutOwnedBuffer[T],
) -> Result[LayoutOwnedBuffer[T], LayoutStorageIssue] {
  guard buffer.value is Some(value) else { return Err(Shape) }
  match share_layout_buffer(ledger, buffer.lease) {
    Err(issue) => Err(issue)
    Ok(lease) => Ok({ lease, value: Some(value), })
  }
}

///|
fn[T] release_owned_layout_buffer(
  ledger : LayoutLedger,
  buffer : LayoutOwnedBuffer[T],
) -> Result[Unit, LayoutStorageIssue] {
  match release_layout_buffer(ledger, buffer.lease) {
    Err(issue) => Err(issue)
    Ok(_) => {
      buffer.value = None
      Ok(())
    }
  }
}

///|
test "owned physical buffers precharge construction and clear released references" {
  let ledger = layout_ledger(1, 9216, 10)
  let builds : Array[Int] = []
  let column : LayoutOwnedBuffer[LayoutColumn] = allocate_owned_layout_buffer(
    ledger,
    1,
    9216,
    fn() {
      builds.push(1)
      Numeric(FixedArray::make(1024, 7.0), FixedArray::make(1024, 1))
    },
  ).unwrap()
  let rejected = allocate_owned_layout_buffer(ledger, 1, 1, fn() {
    builds.push(2)
    0
  })
  assert_true(rejected is Err(Limit))
  assert_eq(builds, [1])
  let view = share_owned_layout_buffer(ledger, column).unwrap()
  release_owned_layout_buffer(ledger, column).unwrap()
  assert_true(column.value is None)
  assert_eq(ledger.bytes.live, 9216)
  {
    guard view.value is Some(Numeric(values, validity)) else { fail("column") }
    assert_eq(values.length(), 1024)
    assert_eq(values[0], 7.0)
    assert_eq(validity[0], 1)
  }
  // Released source handles cannot create another view, even while a sibling lives.
  assert_true(share_owned_layout_buffer(ledger, column) is Err(Shape))
  release_owned_layout_buffer(ledger, view).unwrap()
  assert_true(view.value is None)
  assert_eq(ledger.bytes.live, 0)
  assert_eq(ledger.slots.live, 0)
  assert_eq(ledger.bytes.peak, 9216)
}

///|
fn layout_ledger(slots : Int, bytes : Int, work : Int) -> LayoutLedger {
  {
    slots: { limit: slots, live: 0, peak: 0, },
    bytes: { limit: bytes, live: 0, peak: 0, },
    work: { remaining: work, max_frames: 0, },
  }
}

///|
fn allocate_layout_buffer(
  ledger : LayoutLedger,
  slots : Int,
  bytes : Int,
) -> Result[LayoutBufferLease, LayoutStorageIssue] {
  if slots < 0 || bytes < 0 || ledger.slots.limit < 0 || ledger.bytes.limit < 0 {
    return Err(Shape)
  }
  if !spend_control(ledger.work, 1) ||
    slots > ledger.slots.limit - ledger.slots.live ||
    bytes > ledger.bytes.limit - ledger.bytes.live {
    return Err(Limit)
  }
  // Both reservations are checked before changing either live/peak counter.
  ignore(reserve_slots(ledger.slots, slots))
  ignore(reserve_slots(ledger.bytes, bytes))
  Ok({ buffer: { ledger, slots, bytes, owners: 1, }, released: false, })
}

///|
fn share_layout_buffer(
  ledger : LayoutLedger,
  lease : LayoutBufferLease,
) -> Result[LayoutBufferLease, LayoutStorageIssue] {
  let buffer = lease.buffer
  if lease.released ||
    !physical_equal(ledger, buffer.ledger) ||
    buffer.owners <= 0 {
    return Err(Shape)
  }
  if buffer.owners == 2147483647 || !spend_control(ledger.work, 1) {
    return Err(Limit)
  }
  buffer.owners += 1
  Ok({ buffer, released: false, })
}

///|
// Releasing already-owned capacity must remain possible after work exhaustion.
// This does not refund cumulative work and never revives a released buffer.
fn release_layout_buffer(
  ledger : LayoutLedger,
  lease : LayoutBufferLease,
) -> Result[Unit, LayoutStorageIssue] {
  let buffer = lease.buffer
  if lease.released ||
    !physical_equal(ledger, buffer.ledger) ||
    buffer.owners <= 0 {
    return Err(Shape)
  }
  lease.released = true
  buffer.owners -= 1
  if buffer.owners == 0 {
    release_slots(ledger.slots, buffer.slots)
    release_slots(ledger.bytes, buffer.bytes)
  }
  Ok(())
}

///|
test "shared column buffer remains live until the last view releases it" {
  let ledger = layout_ledger(10, 9216, 3)
  // 1024 numbers, 8 nominal element bytes and one validity byte each.
  let column = allocate_layout_buffer(ledger, 1, 9216).unwrap()
  let first_view = share_layout_buffer(ledger, column).unwrap()
  let second_view = share_layout_buffer(ledger, column).unwrap()
  assert_eq((ledger.slots.live, ledger.bytes.live), (1, 9216))
  assert_eq(ledger.work.remaining, 0)
  release_layout_buffer(ledger, column).unwrap()
  assert_true(release_layout_buffer(ledger, column) is Err(Shape))
  release_layout_buffer(ledger, first_view).unwrap()
  assert_eq(ledger.bytes.live, 9216)
  release_layout_buffer(ledger, second_view).unwrap()
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  assert_eq(ledger.bytes.peak, 9216)
  assert_true(release_layout_buffer(ledger, column) is Err(Shape))
  assert_true(share_layout_buffer(ledger, column) is Err(Shape))
}

///|
test "conversion capacity includes source and destination without partial reservations" {
  for limit in [17, 18] {
    let ledger = layout_ledger(20, limit, 10)
    let source = allocate_layout_buffer(ledger, 8, 0).unwrap()
    let destination = allocate_layout_buffer(ledger, 2, 18)
    if limit == 17 {
      assert_true(destination is Err(Limit))
      assert_eq((ledger.slots.live, ledger.slots.peak), (8, 8))
      assert_eq((ledger.bytes.live, ledger.bytes.peak), (0, 0))
    } else {
      let destination = destination.unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (10, 18))
      release_layout_buffer(ledger, source).unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (2, 18))
      let foreign = layout_ledger(20, 18, 10)
      assert_true(release_layout_buffer(foreign, destination) is Err(Shape))
      assert_true(share_layout_buffer(foreign, destination) is Err(Shape))
      release_layout_buffer(ledger, destination).unwrap()
      assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
      assert_eq(ledger.slots.peak, 10)
    }
  }
}
