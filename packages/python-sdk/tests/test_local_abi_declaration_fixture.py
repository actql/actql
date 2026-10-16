"""Nominal source freshness cannot accept a stale ABI declaration."""
import unittest
from actql_sdk._local_core import LOCAL_CORE_ABI
from local_abi_declaration_fixture import assert_current_local_abi, current_owner_abi


class CurrentABIDeclarationTests(unittest.TestCase):
    def test_current_wrapper_matches_existing_owner_projection(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)

    def test_stale_declaration_refuses(self):
        with self.assertRaises(AssertionError):
            assert_current_local_abi(self, current_owner_abi() - 1)
