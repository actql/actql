///|
extern "js" fn absent_node_source_reference() -> OriginalNodeSourceReference =
  #|() => new Proxy({}, {
  #|  get() { throw new Error('AbsentSourceMustNotRead'); },
  #|  ownKeys() { throw new Error('AbsentSourceMustNotEnumerate'); },
  #|  getOwnPropertyDescriptor() { throw new Error('AbsentSourceMustNotDescribe'); }
  #|})

///|
test "absent actual Node Source issuer refuses before observing a supplied reference" {
  assert_true(
    prepare_node_original_source_child(absent_node_source_reference()) is
    Err(Unavailable),
  )
}
