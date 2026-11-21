///|
test "display labels preserve original optional SQL names and physical slots" {
  let columns : Array[ResultColumn] = [
    { slot: "original0", label: "original0", name_view: None, name: None, },
    {
      slot: "original1",
      label: "original1",
      name_view: None,
      name: Some({ value: "f0_", quoted: false, }),
    },
    {
      slot: "original2",
      label: "original2",
      name_view: None,
      name: Some({ value: "F0__", quoted: true, }),
    },
    { slot: "original3", label: "original3", name_view: None, name: None, },
  ]
  assert_eq(result_column_display_names(columns, 1000), [
    "f0___", "f0_", "F0__", "f3_",
  ])
  assert_true(columns[0].name is None)
  assert_true(columns[3].name is None)
  assert_eq(columns.map(column => column.slot), [
    "original0", "original1", "original2", "original3",
  ])
}

///|
test "display spelling leaves original Unicode names and order unchanged" {
  let columns : Array[ResultColumn] = [
    {
      slot: "a",
      label: "a",
      name_view: None,
      name: Some({ value: "e\u{301}", quoted: true, }),
    },
    { slot: "b", label: "b", name_view: None, name: None, },
    {
      slot: "c",
      label: "c",
      name_view: None,
      name: Some({ value: "f1_", quoted: false, }),
    },
    {
      slot: "d",
      label: "d",
      name_view: None,
      name: Some({ value: "\u{1f600}", quoted: true, }),
    },
  ]
  assert_eq(result_column_display_names(columns, 1000), [
    "e\u{301}", "f1__", "f1_", "\u{1f600}",
  ])
}

///|
test "display comparison work refuses before exceeding its original allowance" {
  let columns : Array[ResultColumn] = [
    { slot: "same", label: "same", name_view: None, name: None, },
  ]
  assert_eq(result_column_display_names(columns, 2), ["f0_"])
  try result_column_display_names(columns, 1) catch {
    Abort(Expression({ issue: @expression.WorkLimit, origin: None, })) => ()
    _ => fail("expected original display-comparison work refusal")
  } noraise {
    _ => fail("one-short display work must refuse")
  }
  assert_true(columns[0].name is None)
  assert_eq(columns[0].slot, "same")
}
