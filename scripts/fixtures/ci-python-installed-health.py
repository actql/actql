"""Accepted typed preparation failure preserves a healthy ordinary Local client."""
import json
from actql import Client, ClientError

client = Client.open()
with client:
    reference = client.new_submission()
    try:
        client.start_source('SELECT (', format='sql', submission_ref=reference)
    except ClientError as error:
        assert error.code == 'SubmissionPreparationFailed', error.code
        assert error.outcome['kind'] == 'preparation_failed'
        assert error.outcome['submissionRef'] == reference
        assert error.outcome['problem']['classification'] == 'invalid_input'
        assert error.outcome['problem']['code'] == 'ClientProgramInvalidInput'
        assert client.lookup_submission(reference) == error.outcome
    else:
        raise AssertionError('Invalid source was accepted as a Run')
    run = client.start_source('SELECT 42 AS n', format='sql', submission_ref=client.new_submission())
    assert run.wait()['status'] == 'succeeded'
    assert run.result('answer').all(max_rows=1) == [{'n': 42}]
try:
    client.start_source('SELECT 1', format='sql')
except ClientError as error:
    assert error.code == 'ClientClosed', error.code
else:
    raise AssertionError('Closed client accepted a new request')
print(json.dumps({'typed_refusal': True, 'healthy_after_refusal': True, 'closed_client_refused': True}))
