///|
test "packed output transport retains original buffer guards and exact scalar byte order" {
  let root = @resources.create_ledger({
    planning_work: 100,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 65536L,
    retained_bytes: 65536L,
    execution_bytes: 16781312L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 16777216L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 4096L, 16, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      2901L, root, capacity, None, pool, 16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(2901L).unwrap()
  let ready = Ref(false)
  let slot = @buffers.reserve_output_buffer(pool, 8, 8L, () => ready.val).unwrap()
  @buffers.supply_buffer_output(pool, slot, b"ABCDEFGH").unwrap()
  value.copies[10] = (slot, 20)
  let before = @buffers.buffer_pool_usage(pool)
  assert_eq(read_packed(2902L, 10, 0, 7), -1L)
  assert_eq(read_packed(2901L, 11, 0, 7), -2L)
  assert_eq(read_packed(2901L, 10, 0, 0), -6L)
  assert_eq(read_packed(2901L, 10, 0, 8), -6L)
  assert_eq(read_packed(2901L, 10, -1, 1), -6L)
  assert_eq(read_packed(2901L, 10, 2147483647, 1), -6L)
  assert_eq(read_packed(2901L, 10, 0, 7), 0x47464544434241L)
  assert_eq(read_packed(2901L, 10, 7, 1), 0x48L)
  assert_eq(read_packed(2901L, 10, 7, 2), -5L)
  assert_eq(@buffers.buffer_pool_usage(pool).allocated, before.allocated)
  assert_eq(@buffers.close_buffer(pool, slot), Err(CleanupPending))
  assert_eq(read_packed(2901L, 10, 0, 1), -5L)
  ready.val = true
  @buffers.close_buffer(pool, slot).unwrap()
  value.copies.remove(10) |> ignore
  assert_eq(read_packed(2901L, 10, 0, 1), -2L)
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  @resources.settle_shared_capacity(capacity).unwrap()
  instance.val = None
}
