"""Typed refusal must preserve a healthy installed ordinary Local client."""
import json
from actql import Client, ClientError, get_submission_check_observation

client = Client.open()
with client:
    try:
        client.start_source('SELECT (', format='sql', submission_ref=client.new_submission())
    except ClientError as error:
        assert error.code == 'SubmissionNotAccepted', error.code
        check = get_submission_check_observation(error)
        assert check['outcome'] == 'completed'
        assert check['report']['verdict'] == 'invalid'
        assert any(reason['code'] == 'query_syntax_invalid' for reason in check['report']['reasons'])
    else:
        raise AssertionError('Invalid source was accepted')
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
