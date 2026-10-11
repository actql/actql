///|
/// Existing authority ports at the final send fence, not fabricated approval,
/// signature, Provider response or actual HTTP success.
test "Cloud Reviewer final row fence refuses current-role or Site loss before the private read" {
  for lost in ["role", "site"] {
    let mut reads = 0
    let current = () => lost != "role"
    let site = () => lost != "site"
    assert_false(
      native_cloud_reviewer_read_current(
        () => {
          reads += 1
          true
        },
        site,
        current,
      ),
    )
    assert_eq(reads, 0)
  }
}

///|
test "Cloud Reviewer final row fence refuses context failure and role or Site loss during the read" {
  for lost in ["context", "role", "site"] {
    let mut reads = 0
    let mut role_current = true
    let mut site_current = true
    let read = () => {
      reads += 1
      if lost == "role" {
        role_current = false
      }
      if lost == "site" {
        site_current = false
      }
      lost != "context"
    }
    assert_false(
      native_cloud_reviewer_read_current(read, () => site_current, () => {
        return role_current
      }),
    )
    assert_eq(reads, 1)
  }
}

///|
test "Cloud Reviewer final row fence rereads each invocation without converting a missing context to resend permission" {
  let mut reads = 0
  let mut present = true
  let read = () => {
    reads += 1
    present
  }
  assert_true(native_cloud_reviewer_read_current(read, () => true, () => true))
  present = false
  assert_false(native_cloud_reviewer_read_current(read, () => true, () => true))
  assert_false(native_cloud_reviewer_read_current(read, () => true, () => true))
  assert_eq(reads, 3)
}
