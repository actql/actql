///|
test "managed slice metadata paired diagnostic" {
  guard @env.get_env_var("ACTQL_MANAGED_SLICE_DIAGNOSTIC") == Some("1") else {
    return
  }
  // Synthetic sealed-index scale model, NOT an execution/completion fixture.
  // Only metadata preparation is timed; no claimed million-row computation
  // or independently validated storage is fabricated by this private setup.
  let owner = capture_fixture()
  let template = managed_read_fixture(owner, Ref(true), index_cells=4)
  for count in [1000, 100000] {
    let cells = Array::makei(count * 2, i => {
      if i % 2 == 0 {
        (1, 1, false)
      } else {
        (4, 1, false)
      }
    })
    let receipt : ManagedOutputValueReceipt = {
      ..template.material.receipt,
      rows: count,
      measured: (count * 3, count * 5, count * 2),
      column_usage: [(count, count), (count * 4, count)],
      column_maxima: [1, 4],
      column_nulls: [0, 0],
      row_measurements: Some(
        managed_row_measurements_from_cells(cells).unwrap(),
      ),
    }
    let source : ManagedCompletedOutput[Int] = {
      ..template,
      material: { ..template.material, receipt, },
    }
    let receiver = typed_receiver(owner, "[{\"filter\":\"n > 0\"}]")
    let input = prepare_managed_producer_read(
      receiver, 0, owner, source, 1000, 10000,
    ).unwrap()
    let plan = prepare_managed_view_plan(
      input,
      [row_kernel(receiver, 0)],
      1000,
      10000,
      100,
    ).unwrap()
    for pair in 0..<8 {
      for leg in 0..<2 {
        let slice = (pair + leg) % 2 == 0
        let clock = @bench.monotonic_clock_start()
        let mut checksum = 0
        for _ in 0..<10 {
          let selected = if slice {
            prepare_managed_view_slice(plan, 0, count, count * 2, count * 10).unwrap()
          } else {
            let occurrences = Array::makei(count, i => i)
            prepare_managed_view_selection(
              plan,
              occurrences,
              count * 2,
              count * 10,
            ).unwrap()
          }
          assert_eq(selected.index.count, count * 2)
          assert_eq(
            managed_view_selection_row(selected, count - 1),
            Some(count - 1),
          )
          checksum += selected.facts.columns[0].bytes +
            selected.facts.columns[1].bytes
          // Discard provisional metadata, identically in both legs. This is
          // not a physical allocator/GC acknowledgement or ledger refund.
          discard_managed_row_measurements(selected.index)
        }
        let elapsed = @bench.monotonic_clock_end(clock)
        assert_eq(checksum, count * 50)
        if pair > 0 {
          println(
            "MANAGED_SLICE rows=" +
            count.to_string() +
            " pair=" +
            pair.to_string() +
            " slice=" +
            slice.to_string() +
            " repetitions=10 elapsed_us=" +
            elapsed.to_string(),
          )
        }
      }
    }
  }
}
