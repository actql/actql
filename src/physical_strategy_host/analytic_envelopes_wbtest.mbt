///|
test "analytic envelope declarations must enforce every selected ceiling" {
  let selected = @connector.analytic_envelope(2, 10L, 20L, 30L, 40L, 50L).unwrap()
  let exact = @connector.analytic_envelope(2, 10L, 20L, 30L, 40L, 50L).unwrap()
  let stricter = @connector.analytic_envelope(2, 9L, 19L, 29L, 39L, 49L).unwrap()
  let looser = @connector.analytic_envelope(2, 10L, 20L, 31L, 40L, 50L).unwrap()
  assert_true(
    analytic_envelopes_satisfied([selected], step => {
      if step == 2 {
        Some(exact)
      } else {
        None
      }
    }),
  )
  assert_true(
    analytic_envelopes_satisfied([selected], step => {
      if step == 2 {
        Some(stricter)
      } else {
        None
      }
    }),
  )
  assert_false(analytic_envelopes_satisfied([selected], _ => None))
  assert_false(
    analytic_envelopes_satisfied([selected], step => {
      if step == 2 {
        Some(looser)
      } else {
        None
      }
    }),
  )
}
