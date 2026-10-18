"""First-domain scalar faults; actual same-provider execution is separate."""
import unittest
from test_local_native_domain_custody import DomainFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainError


class InitialDomainFixture(DomainFixture):
    def __init__(self):
        super().__init__()
        self.host._functions.library.actql_domain_prepare_initial_into = Function(self.initial)

    def initial(self, host, scope, fd, work, attempts, holdings, transfer, reply):
        self.events.append(('initial', host.value, scope.value, fd, work, attempts, holdings, transfer))
        self.live = self.present
        self.result(reply, 1, self.prepare_issue)
        if self.prepare_fault:
            raise self.prepare_fault
        return 0

    def take_initial(self, **changes):
        arguments = dict(work=2, attempts=1, holdings=1, transfer=3)
        arguments.update(changes)
        return _OriginalDomainCustody._prepare_initial_original(
            self.host, self.scope, self.descriptor, self.functions, **arguments)


class InitialDomainTests(unittest.TestCase):
    def test_only_nonbyte_limits_reach_the_original_first_domain_port(self):
        fixture = InitialDomainFixture()
        domain = fixture.take_initial()
        self.assertEqual(fixture.events[0], ('initial', 101, fixture.scope._loan.value, 12, 2, 1, 1, 3))
        self.assertFalse(any(event[0] == 'prepare' for event in fixture.events))
        self.assertIs(domain._owner, fixture.host)
        self.assertIs(domain._scope, fixture.scope)
        self.assertIs(domain._descriptor, fixture.descriptor)
        domain.close_after_stop()
        domain.close_after_stop()
        self.assertTrue(domain._closed)
        self.assertFalse(fixture.descriptor.close_attempted)

    def test_missing_first_port_refuses_without_using_the_old_size_port(self):
        fixture = InitialDomainFixture()
        del fixture.host._functions.library.actql_domain_prepare_initial_into
        before = list(fixture.events)
        with self.assertRaises(AttributeError):
            fixture.take_initial()
        self.assertEqual(fixture.events, before)
        self.assertFalse(fixture.host._busy)
        # The unchanged old explicit path does not require the new export.
        old = fixture.take()
        old.close_after_stop()

    def test_known_partial_refusal_keeps_the_same_domain_until_owner_cleanup(self):
        fixture = InitialDomainFixture()
        fixture.prepare_issue = 6
        with self.assertRaises(_OriginalDomainError) as raised:
            fixture.take_initial()
        domain = raised.exception.cleanup_domain
        self.assertFalse(raised.exception.unknown)
        self.assertEqual(domain._domain.value, 301)
        domain.close_after_stop()
        self.assertTrue(domain._closed)
        self.assertEqual(sum(event[0] == 'initial' for event in fixture.events), 1)

    def test_no_domain_refusal_only_releases_original_reply_data(self):
        fixture = InitialDomainFixture()
        fixture.present = False
        fixture.prepare_issue = 3
        with self.assertRaises(_OriginalDomainError) as raised:
            fixture.take_initial()
        self.assertFalse(raised.exception.unknown)
        self.assertTrue(raised.exception.cleanup_domain._closed)
        self.assertFalse(any(event[0] == 'call' for event in fixture.events))

    def test_lost_prepare_retains_original_reply_and_blocks_cleanup_replay(self):
        fixture = InitialDomainFixture()
        fixture.prepare_fault = OSError('lost original first-domain reply')
        with self.assertRaises(_OriginalDomainError) as raised:
            fixture.take_initial()
        domain = raised.exception.cleanup_domain
        self.assertTrue(raised.exception.unknown)
        self.assertIsNotNone(domain._reply.value)
        self.assertIs(domain._descriptor, fixture.descriptor)
        before = list(fixture.events)
        for operation in (domain.current, domain.close_after_stop):
            with self.assertRaises(_OriginalDomainError) as again:
                operation()
            self.assertIs(again.exception, raised.exception)
        self.assertEqual(fixture.events, before)

    def test_busy_entry_is_a_known_local_refusal_and_preserves_owning_busy(self):
        fixture = InitialDomainFixture()
        fixture.host._busy = True
        before = list(fixture.events)
        with self.assertRaises(ValueError):
            fixture.take_initial()
        self.assertTrue(fixture.host._busy)
        self.assertEqual(fixture.events, before)
        fixture.host._busy = False
        fixture.take_initial().close_after_stop()

    def test_bool_and_overflow_limits_refuse_before_first_call(self):
        fixture = InitialDomainFixture()
        before = list(fixture.events)
        for change in ({'work': True}, {'attempts': 2**31}, {'transfer': 2**63}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                fixture.take_initial(**change)
        self.assertEqual(fixture.events, before)
