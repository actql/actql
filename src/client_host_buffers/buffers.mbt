///|
/// Instance-private transfer storage. This is not a Run or recovery Owner.
/// Capacity and borrower retirement belong to the existing physical Ledger.
pub struct BufferPool {
  ledger : @resources.Ledger
  capacity : @resources.SharedCapacity
  max_slots : Int
  max_wire_bytes : Int
  mut next_serial : Int
  mut live_borrows : Int
  mut slots : Array[BufferSlot]
  mut closing : Bool
  mut settled : Bool
}

///|
pub struct BufferSlot {
  owner : BufferPool
  serial : Int
  allocation : @resources.SharedAllocation
  wire_length : Int
  cleanup : () -> Bool
  mut output_only : Bool
  mut bytes : Array[Byte]
  mut wire : Bytes?
  mut written : Int
  mut source : @source.Node?
  mut input_complete : Bool
  mut retired : Bool
  mut cleaned : Bool
}

///|
pub struct BufferBorrow {
  owner : BufferPool
  slot : BufferSlot
  borrow : @resources.SharedBorrow
  physical_stop : () -> Bool
  mut returned : Bool
}

///|
pub(all) enum BufferIssue {
  InvalidLimits
  Closed
  ForeignOwner
  Capacity
  InvalidPosition
  InvalidByte
  Incomplete
  Input(@source.ParseError)
  CleanupPending
  Resource(@resources.LedgerIssue)
} derive(Eq, Debug)

///|
/// One pool reserves its total allowance once. Suballocations account for all
/// concurrent transfers, including physical copies outside linear memory.
pub fn open_pool(
  total_bytes : Int64,
  max_slots : Int,
  max_wire_bytes : Int,
) -> Result[BufferPool, BufferIssue] {
  if total_bytes <= 0L ||
    max_slots < 1 ||
    max_slots > 1024 ||
    max_wire_bytes < 1 {
    return Err(InvalidLimits)
  }
  let ledger = match
    @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: total_bytes,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  open_pool_on_ledger(ledger, total_bytes, max_slots, max_wire_bytes)
}

///|
/// Compose transfers with the Host's existing root Ledger. Workspace and other
/// pools compete for that same allowance; this pool settles only its own lease.
pub fn open_pool_on_ledger(
  ledger : @resources.Ledger,
  total_bytes : Int64,
  max_slots : Int,
  max_wire_bytes : Int,
) -> Result[BufferPool, BufferIssue] {
  if total_bytes <= 0L ||
    max_slots < 1 ||
    max_slots > 1024 ||
    max_wire_bytes < 1 {
    return Err(InvalidLimits)
  }
  let capacity = match @resources.reserve_shared_capacity(ledger, total_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  Ok({
    ledger,
    capacity,
    max_slots,
    max_wire_bytes,
    next_serial: 1,
    live_borrows: 0,
    slots: [],
    closing: false,
    settled: false,
  })
}

///|
/// Physical adapters supply measured copy capacity before allocating it.
/// Mutable and immutable wire payloads inside Wasm are charged separately,
/// including their overlap during sealing, without treating equal
/// bytes as one allocation. The immutable cleanup callback owns that copy.
pub fn reserve_buffer(
  pool : BufferPool,
  wire_bytes : Int,
  physical_copy_bytes : Int64,
  cleanup : () -> Bool,
) -> Result[BufferSlot, BufferIssue] {
  if pool.closing {
    return Err(Closed)
  }
  if wire_bytes < 0 ||
    wire_bytes > pool.max_wire_bytes ||
    physical_copy_bytes < 0L ||
    physical_copy_bytes > 9223372036854775807L - 2L * wire_bytes.to_int64() {
    return Err(InvalidLimits)
  }
  if pool.slots.length() + pool.live_borrows >= pool.max_slots ||
    pool.next_serial == 2147483647 {
    return Err(Capacity)
  }
  let allocation = match
    @resources.allocate_shared_capacity(
      pool.capacity,
      physical_copy_bytes + 2L * wire_bytes.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let slot = {
    owner: pool,
    serial: pool.next_serial,
    allocation,
    wire_length: wire_bytes,
    cleanup,
    output_only: false,
    // Keep reservation free of the large transfer allocation. The caller
    // receives custody before fill can trap while growing linear memory.
    bytes: [],
    wire: None,
    written: 0,
    source: None,
    input_complete: false,
    retired: false,
    cleaned: false,
  }
  pool.next_serial += 1
  pool.slots.push(slot)
  Ok(slot)
}

///|
pub fn buffer_serial(slot : BufferSlot) -> Int {
  slot.serial
}

///|
/// Reserve custody before a Core producer allocates its immutable wire. The
/// producer must bound its own encoding workspace; this pool accounts for
/// retained wire and transfer overlap, not the producer's entire Core heap.
pub fn reserve_output_buffer(
  pool : BufferPool,
  max_wire_bytes : Int,
  physical_copy_bytes : Int64,
  cleanup : () -> Bool,
) -> Result[BufferSlot, BufferIssue] {
  match reserve_buffer(pool, max_wire_bytes, physical_copy_bytes, cleanup) {
    Err(issue) => Err(issue)
    Ok(slot) => {
      slot.output_only = true
      Ok(slot)
    }
  }
}

///|
/// Publish once into the exact reserved output. Core-produced bytes are not
/// decoded as authoring input and cannot acquire a source-node capability.
pub fn supply_buffer_output(
  pool : BufferPool,
  slot : BufferSlot,
  wire : Bytes,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  if pool.closing || slot.retired || slot.cleaned || slot.input_complete {
    return Err(Closed)
  }
  if !slot.output_only || wire.length() > slot.wire_length {
    return Err(InvalidLimits)
  }
  slot.wire = Some(wire)
  slot.input_complete = true
  Ok(())
}

///|
pub fn buffer_length(pool : BufferPool, slot : BufferSlot) -> Int? {
  buffer_wire(pool, slot).map(wire => wire.length())
}

///|
pub fn buffer_output_limit(pool : BufferPool, slot : BufferSlot) -> Int? {
  if !physical_equal(pool, slot.owner) ||
    pool.closing ||
    slot.retired ||
    slot.cleaned ||
    slot.input_complete ||
    !slot.output_only {
    None
  } else {
    Some(slot.wire_length)
  }
}

///|
pub fn lookup_buffer(pool : BufferPool, serial : Int) -> BufferSlot? {
  pool.slots.iter().find_first(slot => slot.serial == serial && !slot.cleaned)
}

///|
/// Exactly one in-order bounded chunk. No mutation or callback is allowed for
/// a foreign, retired, input_complete, overlapping, or out-of-range request.
pub fn fill_buffer(
  pool : BufferPool,
  slot : BufferSlot,
  start : Int,
  count : Int,
  read_byte : (Int) -> Byte?,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  if pool.closing ||
    slot.retired ||
    slot.cleaned ||
    slot.input_complete ||
    slot.output_only {
    return Err(Closed)
  }
  if start != slot.written ||
    count < 0 ||
    count > 16384 ||
    count > slot.wire_length - slot.written {
    return Err(InvalidPosition)
  }
  if count > 0 && slot.bytes.is_empty() {
    slot.bytes = Array::make(slot.wire_length, 0)
  }
  for index in start..<(start + count) {
    guard read_byte(index) is Some(byte) else { return Err(InvalidByte) }
    slot.bytes[index] = byte
  }
  slot.written += count
  Ok(())
}

///|
/// The common source decoder preserves exact bytes, Unicode and NULL/absence.
/// This is input transfer admission, not Program checking or Run admission.
pub fn seal_buffer(
  pool : BufferPool,
  slot : BufferSlot,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  if pool.closing ||
    slot.retired ||
    slot.cleaned ||
    slot.input_complete ||
    slot.output_only {
    return Err(Closed)
  }
  if slot.written != slot.wire_length {
    return Err(Incomplete)
  }
  if max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let wire = Bytes::from_array(slot.bytes)
  let node = match
    @source.parse_json_bytes_preserving(wire, {
      max_input_bytes: pool.max_wire_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  slot.source = Some(node)
  slot.wire = Some(wire)
  slot.bytes = []
  slot.input_complete = true
  Ok(())
}

///|
pub fn buffer_source(pool : BufferPool, slot : BufferSlot) -> @source.Node? {
  if !physical_equal(pool, slot.owner) ||
    pool.closing ||
    slot.retired ||
    slot.cleaned ||
    !slot.input_complete {
    None
  } else {
    slot.source
  }
}

///|
/// Immutable original bytes for a trusted Core consumer. A consumer retaining
/// this view must hold its exact borrow until it has finished using the bytes.
pub fn buffer_wire(pool : BufferPool, slot : BufferSlot) -> Bytes? {
  if !physical_equal(pool, slot.owner) ||
    pool.closing ||
    slot.retired ||
    slot.cleaned ||
    !slot.input_complete {
    None
  } else {
    slot.wire
  }
}

///|
pub fn buffer_byte(pool : BufferPool, slot : BufferSlot, index : Int) -> Byte? {
  if !physical_equal(pool, slot.owner) ||
    slot.retired ||
    slot.cleaned ||
    !slot.input_complete ||
    index < 0 ||
    index >= slot.wire_length {
    None
  } else {
    match slot.wire {
      Some(wire) => wire.get(index)
      None => None
    }
  }
}

///|
pub fn borrow_buffer(
  pool : BufferPool,
  slot : BufferSlot,
  physical_stop : () -> Bool,
) -> Result[BufferBorrow, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  if pool.closing || slot.retired || slot.cleaned || !slot.input_complete {
    return Err(Closed)
  }
  if pool.slots.length() + pool.live_borrows >= pool.max_slots {
    return Err(Capacity)
  }
  let borrow = match
    @resources.borrow_shared_capacity(pool.capacity, slot.allocation) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  pool.live_borrows += 1
  Ok({ owner: pool, slot, borrow, physical_stop, returned: false, })
}

///|
/// A cancelled waiter is not a physical stop acknowledgement. Until the
/// adapter confirms it, the common Ledger retains the same borrower token.
pub fn return_buffer_borrow(
  pool : BufferPool,
  borrow : BufferBorrow,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, borrow.owner) {
    return Err(ForeignOwner)
  }
  if borrow.returned {
    return Ok(())
  }
  if !(borrow.physical_stop)() {
    return Err(CleanupPending)
  }
  match @resources.return_shared_capacity(borrow.borrow) {
    Ok(_) => ()
    Err(issue) => return Err(Resource(issue))
  }
  borrow.returned = true
  pool.live_borrows -= 1
  Ok(())
}

///|
pub fn close_buffer(
  pool : BufferPool,
  slot : BufferSlot,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  if slot.cleaned {
    return Ok(())
  }
  if !slot.retired {
    @resources.retire_shared_capacity(slot.allocation)
    slot.retired = true
  }
  if @resources.shared_allocation_usage(slot.allocation).readers != 0 ||
    !(slot.cleanup)() {
    return Err(CleanupPending)
  }
  match @resources.release_shared_capacity(slot.allocation) {
    Ok(_) => ()
    Err(issue) => return Err(Resource(issue))
  }
  slot.bytes = []
  slot.wire = None
  slot.source = None
  slot.cleaned = true
  pool.slots = pool.slots.filter(value => !physical_equal(value, slot))
  Ok(())
}

///|
pub fn buffer_pool_usage(pool : BufferPool) -> @resources.SharedCapacityUsage {
  @resources.shared_capacity_usage(pool.capacity)
}

///|
pub fn buffer_pool_ledger_usage(pool : BufferPool) -> @resources.LedgerUsage {
  @resources.ledger_usage(pool.ledger)
}

///|
/// Closing blocks new admission. Failed cleanup keeps its allocation and
/// shared reservation; retry never allocates another pool or repeats input.
pub fn close_pool(pool : BufferPool) -> Result[Unit, BufferIssue] {
  if pool.settled {
    return Ok(())
  }
  if !pool.closing {
    match @resources.close_shared_capacity(pool.capacity) {
      Ok(_) => ()
      Err(issue) => return Err(Resource(issue))
    }
    pool.closing = true
  }
  let mut pending = false
  for slot in pool.slots.copy() {
    if close_buffer(pool, slot) is Err(_) {
      pending = true
    }
  }
  if pending {
    return Err(CleanupPending)
  }
  match @resources.settle_shared_capacity(pool.capacity) {
    Ok(_) => ()
    Err(issue) => return Err(Resource(issue))
  }
  pool.settled = true
  Ok(())
}
