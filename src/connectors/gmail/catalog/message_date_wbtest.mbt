///|
test "Gmail Date converts original numeric zones without a host date or binary64 clock" {
  for
    (text, utc) in [
      ("Fri, 21 Nov 1997 09:55:06 -0600", "1997-11-21T15:55:06.000Z"),
      ("21 Nov 1997 09:55 +0000", "1997-11-21T09:55:00.000Z"),
      ("21 Nov 1997 09:55 -0000", "1997-11-21T09:55:00.000Z"),
      ("1 Jan 2000 00:15 +0030", "1999-12-31T23:45:00.000Z"),
      ("31 Dec 1999 23:45 -0030", "2000-01-01T00:15:00.000Z"),
      ("21Nov9709:55GMT", "1997-11-21T09:55:00.000Z"),
      ("21 Nov 97 09:55 EST", "1997-11-21T14:55:00.000Z"),
      ("21 Nov 049 09:55 UT", "1949-11-21T09:55:00.000Z"),
      ("21 Nov 49 09:55 UT", "2049-11-21T09:55:00.000Z"),
    ] {
    assert_eq(gmail_header_date(text, 1024, 8), Ok(utc))
  }
}

///|
test "Gmail Date retains RFC comments and folding while enforcing numeric zone FWS" {
  assert_eq(
    gmail_header_date(
      "(outer(inner\\)))Fri,(day)21 Nov\r\n\t1997 09(comment):55:06 \t-0600(end)",
      1024, 8,
    ),
    Ok("1997-11-21T15:55:06.000Z"),
  )
  for
    text in [
      "21 Nov 1997 09:55(comment)+0000", "21 Nov 1997 09:55+0000", "21 Nov 1997 09:55\n +0000",
      "21 Nov 1997 09:55\r\n+0000", "21 Nov 1997 09:55 +0000(unclosed", "21 Nov 1997 09:55 +0000)unmatched",
    ] {
    assert_eq(gmail_header_date(text, 1024, 8), Err(Malformed))
  }
}

///|
test "Gmail Date distinguishes genuinely malformed fields from valid unrepresentable instants" {
  for
    text in [
      "Thu, 21 Nov 1997 09:55:06 -0600", "29 Feb 1900 09:55 +0000", "31 Apr 2000 09:55 +0000",
      "0 Nov 1997 09:55 +0000", "21 Nov 1899 09:55 +0000", "21 Nov 1997 24:00 +0000",
      "21 Nov 1997 09:60 +0000", "21 Nov 1997 09:55:61 +0000", "21 Nov 1997 09:55:06.5 +0000",
      "21 Nov 1997 09:55 +0060", "21 Nov 1997 09:55 +0000 junk",
    ] {
    assert_eq(gmail_header_date(text, 1024, 8), Err(Malformed))
  }
  for
    text in [
      "31 Dec 2016 23:59:60 +0000", "1 Jan 10000 00:00 +0000", "31 Dec 9999 23:59 -0100",
    ] {
    assert_eq(gmail_header_date(text, 1024, 8), Err(Unsupported))
  }
  assert_eq(
    gmail_header_date("29 Feb 2000 09:55 +0000", 1024, 8),
    Ok("2000-02-29T09:55:00.000Z"),
  )
}

///|
test "Gmail Date work exhaustion never becomes malformed-header fallback" {
  let text = "21 Nov 1997 09:55 +0000"
  assert_eq(gmail_header_date(text, text.length() - 1, 8), Err(BudgetExceeded))
  assert_eq(
    gmail_header_date(text, text.length(), 8),
    Ok("1997-11-21T09:55:00.000Z"),
  )
  assert_eq(gmail_header_date("(a(b))" + text, 1024, 1), Err(BudgetExceeded))
  assert_eq(gmail_header_date("(a)" + text, 1024, 0), Err(BudgetExceeded))
}
