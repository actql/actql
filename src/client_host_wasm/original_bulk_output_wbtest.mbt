///|
test "original bulk output keeps exact range and cleanup guards without copying or reissuing" {
  let root = @resources.create_ledger({
    planning_work: 100,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 65536L,
    retained_bytes: 65536L,
    execution_bytes: 16781312L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 65536L, 16, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      3901L,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(3901L).unwrap()
  let ready = Ref(false)
  let slot = @buffers.reserve_output_buffer(pool, 16385, 16385L, () => ready.val).unwrap()
  let original = Bytes::from_array(Array::make(16385, b"A"[0]))
  @buffers.supply_buffer_output(pool, slot, original).unwrap()
  value.copies[10] = (slot, 20)
  let before = @buffers.buffer_pool_usage(pool)
  assert_eq(read_block(3902L, 10, 0, 1), -1)
  assert_eq(read_block(3901L, 11, 0, 1), -2)
  for
    (start, length) in [
      (0, 0),
      (0, 16385),
      (-1, 1),
      (16385, 1),
      (2147483647, 1),
    ] {
    assert_eq(read_block(3901L, 10, start, length), -5)
  }
  let first = read_block(3901L, 10, 0, 16384)
  assert_true(first >= 0)
  assert_eq(read_block(3901L, 10, 16384, 1), first + 16384)
  assert_eq(@buffers.buffer_wire(pool, slot), Some(original))
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, before.allocated)
  assert_eq(@buffers.close_buffer(pool, slot), Err(CleanupPending))
  assert_eq(read_block(3901L, 10, 0, 1), -5)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, before.allocated)
  ready.val = true
  @buffers.close_buffer(pool, slot).unwrap()
  value.copies.remove(10) |> ignore
  assert_eq(read_block(3901L, 10, 0, 1), -2)
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}
