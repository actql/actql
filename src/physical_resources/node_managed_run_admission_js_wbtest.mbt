///|
extern "js" fn absent_node_managed_run_reference() -> OriginalNodeManagedRunReference =
  #|() => new Proxy({}, {
  #|  get() { throw new Error('AbsentRunMustNotRead'); },
  #|  ownKeys() { throw new Error('AbsentRunMustNotEnumerate'); },
  #|  getOwnPropertyDescriptor() { throw new Error('AbsentRunMustNotDescribe'); }
  #|})

///|
test "absent actual Node managed Run issuer refuses before observing a supplied reference" {
  assert_true(
    prepare_node_managed_run_admission(
      absent_node_managed_run_reference(),
      Ref(1),
    )
    is Err(Unavailable),
  )
}

///|
test "absent separate Node Mock purpose never falls back to Source ports or reads a supplied reference" {
  assert_true(
    prepare_node_local_mock_model_run_admission(
      absent_node_managed_run_reference(),
      Ref(1),
    )
    is Err(Unavailable),
  )
}

///|
test "absent separate Node Content purpose never falls back to Source or Model ports" {
  assert_true(
    prepare_node_local_content_run_admission(
      absent_node_managed_run_reference(),
      Ref(1),
    )
    is Err(Unavailable),
  )
}
