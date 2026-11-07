///|
fn bridge_confirmation_body() -> Bytes {
  @utf8.encode(
    (
      {
        "data": {
          "node": {
            "__typename": "IssueComment",
            "id": "IC_original",
            "databaseId": 7,
            "body": ("logical\n\n<!-- actql:effect:sha256:" +
            "a".repeat(64) +
            " -->").to_json(),
            "issue": { "__typename": "Issue", "id": "I_original" },
            "repository": {
              "__typename": "Repository",
              "id": "R_original",
              "databaseId": 13,
              "nameWithOwner": "o/r",
            },
          },
        },
      } : Json).stringify(),
  )
}

///|
test "comment confirmation bridge returns only matched original provider DATA" {
  let original = bridge_confirmation_body()
  let projected = github_comment_confirmation_json(
    original,
    10000,
    500,
    16,
    7.0,
    "IC_original",
    "I_original",
    "R_original",
    13.0,
    "o/r",
    "logical",
    "sha256:" + "a".repeat(64),
  )
  let expected : Json = {
    "comment": { "id": 7, "node_id": "IC_original", "subject_id": "I_original" },
  }
  let actual = @json.parse(projected) catch {
    _ => abort("invalid provider DATA JSON")
  }
  assert_eq(actual, expected)
  let foreign = github_comment_confirmation_json(
    original,
    10000,
    500,
    16,
    7.0,
    "IC_original",
    "I_original",
    "R_original",
    13.0,
    "o/r",
    "logical",
    "sha256:" + "b".repeat(64),
  )
  assert_true(foreign.contains("refused"))
  assert_false(foreign.contains("\"comment\""))
}

///|
test "comment confirmation bridge refuses lossy native IDs before conversion" {
  for value in [0.0, -1.0, 1.5, 2147483648.0, 0.0 / 0.0, 1.0 / 0.0] {
    for (comment, repository) in [(value, 13.0), (7.0, value)] {
      let projected = github_comment_confirmation_json(
        b"{}",
        10000,
        500,
        16,
        comment,
        "IC_original",
        "I_original",
        "R_original",
        repository,
        "o/r",
        "logical",
        "sha256:" + "a".repeat(64),
      )
      assert_true(projected.contains("InvalidResponse"))
      assert_false(projected.contains("\"comment\""))
    }
  }
}

///|
test "comment confirmation bridge preserves exact opaque selector in its pure request" {
  let request = github_comment_confirmation_request_json("IC_original")
  assert_true(request.contains("ActqlConfirmComment"))
  assert_true(request.contains("IC_original"))
  assert_false(request.contains("mutation "))
  assert_true(github_comment_confirmation_request_json("").contains("refused"))
}
