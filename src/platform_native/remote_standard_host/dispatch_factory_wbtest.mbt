///|
fn occurrence_factory_request(
  binding : @remote.RemoteInputBinding,
  attempt : Int,
  dispatch : String,
) -> @remote.DispatchRequest {
  let cid = "sha256:" + "a".repeat(64)
  @remote.prepare_dispatch_request(
    "current-authority",
    cid,
    "checked-consumer",
    attempt,
    dispatch,
    "current-site",
    1,
    cid,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_input_binding_cid(binding),
    cid,
    cid,
    cid,
    cid,
  ).unwrap()
}

///|
test "dispatch owned input factory refuses equal binding on another occurrence before opening" {
  let binding = @remote.prepare_remote_input_binding("{}", 100).unwrap()
  let original = occurrence_factory_request(binding, 1, "original")
  let opened = Ref(0)
  let factory = register_native_remote_standard_dispatch_run_factory(
    original,
    binding,
    () => {
      opened.val += 1
      Err(reject_native_remote_standard_input("probe-owner").unwrap())
    },
  ).unwrap()
  for
    request in [
      occurrence_factory_request(binding, 2, "different-attempt"),
      occurrence_factory_request(binding, 1, "different-dispatch"),
    ] {
    let failure = factory.resolve(request, binding).unwrap_err()
    assert_eq(
      native_remote_standard_input_failure_code(failure),
      "foreign-input-binding",
    )
    assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
    assert_eq(opened.val, 0)
  }
  let failure = factory.resolve(original, binding).unwrap_err()
  assert_eq(native_remote_standard_input_failure_code(failure), "probe-owner")
  assert_eq(opened.val, 1)
  let foreign = @remote.prepare_remote_input_binding("[]", 100).unwrap()
  assert_true(
    register_native_remote_standard_dispatch_run_factory(original, foreign, () => {
      opened.val += 1
      Err(reject_native_remote_standard_input("probe-owner").unwrap())
    })
    is Err(InvalidConfiguration),
  )
  assert_eq(opened.val, 1)
}
