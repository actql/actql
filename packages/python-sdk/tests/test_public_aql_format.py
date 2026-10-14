import unittest
from actql_sdk import _wire
from typing import get_args
from actql_sdk._public_types import SourceFormat

class PublicAqlFormatTests(unittest.TestCase):
    def test_aql_check_and_submit_preserve_original_spelling(self):
        self.assertIn("aql", get_args(SourceFormat))
        connection = {"mode": "remote", "owner": "remote", "consentRefs": [], "runners": []}
        input_ = {"text": "SELECT @p AS id", "format": "aql", "parameterDeclarations": {"p": {"type": "number", "nullable": False}}}
        submit = {"connection": connection, "kind": "aql", "requestId": "original-aql", "input": input_, "parameters": {"p": 1}}
        self.assertTrue(_wire.valid_body("submit", submit))
        self.assertTrue(_wire.valid_body("check", {"connection": connection, "kind": "text", "scope": "bound_input", "input": input_, "parameters": {"p": 1}}))
        self.assertEqual(input_["format"], "aql")
        self.assertFalse(_wire.valid_body("submit", submit | {"input": input_ | {"format": "aql2"}}))
        self.assertFalse(_wire.valid_body("submit", submit | {"input": input_ | {"parameterDeclarations": []}}))
