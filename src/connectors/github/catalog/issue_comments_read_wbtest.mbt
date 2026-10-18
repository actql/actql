///|
fn comment_sequence(
  max_pages? : Int = 20,
  max_subjects? : Int = 10,
  max_rows? : Int = 10,
) -> IssueCommentsRead {
  begin_issue_comments_read(
    comment_read_subject().repository,
    { max_bytes: 65536, max_nodes: 1000, max_depth: 32, max_rows, },
    max_pages,
    max_subjects,
  ).unwrap()
}

///|
fn sequence_subject_page(kind : String) -> String {
  comment_subjects_body(kind).replace(
    old="\"hasNextPage\":true,\"endCursor\":\"subjects-next\"",
    new="\"hasNextPage\":false,\"endCursor\":null",
  )
}

///|
fn sequence_next(read : IssueCommentsRead) -> String {
  issue_comments_read_next_request(read, 100).unwrap().unwrap()
}

///|
fn sequence_accept(read : IssueCommentsRead, body : String) -> Unit {
  issue_comments_read_accept(read, @utf8.encode(body)).unwrap()
}

///|
test "comment read sequence completes both native families without inventing parent IDs" {
  let read = comment_sequence()
  assert_true(sequence_next(read).contains("issues(first:"))
  sequence_accept(read, sequence_subject_page("Issue"))
  assert_eq(issue_comments_read_take_page(read).unwrap(), None)
  assert_true(sequence_next(read).contains("... on Issue {"))
  sequence_accept(read, comment_read_body())
  let issue = issue_comments_read_take_page(read).unwrap().unwrap()
  assert_eq(issue.rows[0].subject_number, 7L)
  assert_true(sequence_next(read).contains("pullRequests(first:"))
  // A different real PR original is selected from its own native enumeration.
  let pr_subject = sequence_subject_page("PullRequest")
    .replace(old="S_original", new="PR_original")
    .replace(old="\"number\":7", new="\"number\":8")
  sequence_accept(read, pr_subject)
  assert_true(sequence_next(read).contains("... on PullRequest {"))
  let pr = comment_read_body(kind="PullRequest", key="9223372036854775807")
    .replace(old="S_original", new="PR_original")
    .replace(old="\"number\":7", new="\"number\":8")
  sequence_accept(read, pr)
  let page = issue_comments_read_take_page(read).unwrap().unwrap()
  assert_eq(page.rows[0].subject_number, 8L)
  assert_eq(page.rows[0].id, 9223372036854775807L)
  assert_eq(issue_comments_read_next_request(read, 100).unwrap(), None)
}

///|
test "comment read sequence refuses response without request and a replacement pending request" {
  let no_request = comment_sequence()
  assert_true(
    issue_comments_read_accept(
      no_request,
      @utf8.encode(sequence_subject_page("Issue")),
    )
    is Err(_),
  )
  assert_true(issue_comments_read_next_request(no_request, 100) is Err(_))
  let pending = comment_sequence()
  sequence_next(pending) |> ignore
  assert_true(issue_comments_read_next_request(pending, 100) is Err(_))
  assert_true(
    issue_comments_read_accept(
      pending,
      @utf8.encode(sequence_subject_page("Issue")),
    )
    is Err(_),
  )
}

///|
test "comment read sequence keeps complete page projection separate from charge consumption" {
  let read = comment_sequence()
  sequence_next(read) |> ignore
  sequence_accept(read, sequence_subject_page("Issue"))
  sequence_next(read) |> ignore
  sequence_accept(read, comment_read_body())
  // A completed page must be projected before another response can be charged.
  assert_true(issue_comments_read_next_request(read, 100) is Err(_))
  assert_true(issue_comments_read_take_page(read) is Err(_))
}

///|
test "comment read sequence rejects repeated dependent cursor and stays refused after restored bytes" {
  let read = comment_sequence()
  sequence_next(read) |> ignore
  sequence_accept(read, sequence_subject_page("Issue"))
  sequence_next(read) |> ignore
  let first = comment_read_body().replace(
    old="\"hasNextPage\":false,\"endCursor\":null",
    new="\"hasNextPage\":true,\"endCursor\":\"next-comment\"",
  )
  sequence_accept(read, first)
  issue_comments_read_take_page(read).unwrap() |> ignore
  assert_true(sequence_next(read).contains("next-comment"))
  let repeated = first.replace(old="9007199254740993", new="9007199254740994")
  assert_true(
    issue_comments_read_accept(read, @utf8.encode(repeated))
    is Err(MissingCursor),
  )
  assert_true(
    issue_comments_read_accept(
      read,
      @utf8.encode(comment_read_body(key="9007199254740994")),
    )
    is Err(_),
  )
  assert_true(issue_comments_read_take_page(read) is Err(_))
}

///|
test "comment read sequence shares page subject and row bounds across independent originals" {
  let pages = comment_sequence(max_pages=1)
  sequence_next(pages) |> ignore
  sequence_accept(pages, sequence_subject_page("Issue"))
  assert_true(
    issue_comments_read_next_request(pages, 100) is Err(BudgetExceeded),
  )
  let subjects = comment_sequence(max_subjects=1)
  sequence_next(subjects) |> ignore
  sequence_accept(subjects, sequence_subject_page("Issue"))
  sequence_next(subjects) |> ignore
  sequence_accept(subjects, comment_read_body())
  issue_comments_read_take_page(subjects).unwrap() |> ignore
  sequence_next(subjects) |> ignore
  assert_true(
    issue_comments_read_accept(
      subjects,
      @utf8.encode(
        sequence_subject_page("PullRequest").replace(
          old="S_original",
          new="PR_other",
        ),
      ),
    )
    is Err(BudgetExceeded),
  )
  let duplicate = comment_sequence()
  sequence_next(duplicate) |> ignore
  sequence_accept(duplicate, sequence_subject_page("Issue"))
  sequence_next(duplicate) |> ignore
  sequence_accept(duplicate, comment_read_body())
  issue_comments_read_take_page(duplicate).unwrap() |> ignore
  sequence_next(duplicate) |> ignore
  sequence_accept(
    duplicate,
    sequence_subject_page("PullRequest").replace(
      old="S_original",
      new="PR_other",
    ),
  )
  sequence_next(duplicate) |> ignore
  assert_true(
    issue_comments_read_accept(
      duplicate,
      @utf8.encode(
        comment_read_body(kind="PullRequest").replace(
          old="S_original",
          new="PR_other",
        ),
      ),
    )
    is Err(Row(InvalidField("fullDatabaseId"))),
  )
}

///|
test "comment read sequence retains explicit request cardinality and original subject membership" {
  let read = comment_sequence()
  issue_comments_read_next_request(read, 1).unwrap() |> ignore
  let double = sequence_subject_page("Issue").replace(
    old="\"nodes\":[",
    new="\"nodes\":[{\"__typename\":\"Issue\",\"id\":\"other\",\"number\":8,\"updatedAt\":\"2026-10-01T00:00:00Z\"},",
  )
  assert_true(
    issue_comments_read_accept(read, @utf8.encode(double))
    is Err(BudgetExceeded),
  )
  let foreign = comment_sequence()
  sequence_next(foreign) |> ignore
  sequence_accept(foreign, sequence_subject_page("Issue"))
  sequence_next(foreign) |> ignore
  assert_true(
    issue_comments_read_accept(
      foreign,
      @utf8.encode(comment_read_body().replace(old="S_original", new="foreign")),
    )
    is Err(ForeignSubject),
  )
  assert_true(
    issue_comments_read_accept(foreign, @utf8.encode(comment_read_body()))
    is Err(_),
  )
}
