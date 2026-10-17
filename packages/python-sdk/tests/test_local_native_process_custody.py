"""Independent opaque slot/fault counters; actual current DLL cases are separate."""
import copy
import pickle
import unittest
from test_local_native_domain_custody import DomainFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_process_custody import (
    _OriginalInstalledProcessCustody as Custody,
    _OriginalInstalledProcessFunctions as Functions,
    _OriginalInstalledProcessError as Error,
)


class ProcessFixture:
    def __init__(self, *, original=None, domain=None):
        self.original = original if original is not None else DomainFixture()
        self.domain = domain if domain is not None else self.original.take()
        self.events, self.facts = [], {}
        self.preparations = []
        self.issue, self.present = 0, True
        self.prepare_fault = self.capture_fault = self.call_fault = self.finish_fault = None
        self.wrong_operation = None
        library = self.original.host._functions.library
        calls = {'prepare_utf16_into': self.prepare, 'operate_into': self.operate,
                 'child_utf16_into': self.child, 'originals_into': self.originals,
                 'operation': lambda p: self.facts[p.value][0],
                 'issue_family': lambda p: self.facts[p.value][1],
                 'copy_facts': self.copy_facts, 'drop_reply': self.drop,
                 'finish_closed_data': self.finish, 'finish_refused_prepare': self.refused}
        for name, call in calls.items(): setattr(library, 'actql_process_' + name, Function(call))
        self.functions = Functions(library)

    def reply(self, slot, operation):
        key = 800 + len(self.facts)
        self.facts[key] = (self.wrong_operation or operation, self.issue)
        slot._obj.value = key

    def prepare(self, h, d, path, units, fd, nonce, retained, execution, reply):
        self.events.append(('prepare', h.value, d.value, fd))
        self.preparations.append((nonce, retained, execution))
        self.reply(reply, 1)
        if self.prepare_fault: raise self.prepare_fault
        return 0

    def originals(self, r, h, d, p, c, f):
        h._obj.value, d._obj.value = 101, 301
        if self.present: p._obj.value, c._obj.value, f._obj.value = 401, 501, 601
        if self.capture_fault: raise self.capture_fault
        return 0

    def operate(self, h, d, p, operation, reply):
        self.events.append(('operate', operation))
        self.reply(reply, operation)
        if self.call_fault: raise self.call_fault
        return 0

    def child(self, h, d, p, text, units, arguments, argc, environment, envc, reply):
        self.events.append(('child', bytes(arguments), bytes(environment)))
        self.reply(reply, 10)
        return 0

    def copy_facts(self, r, h, d, p, output):
        output[:] = (21, 22, 23, 2)
        return 0

    def drop(self, reply, h, d, p):
        self.events.append(('drop', reply._obj.value))
        reply._obj.value = None
        return 0

    def finish(self, *slots):
        self.events.append(('finish',))
        for slot in slots: slot._obj.value = None
        if self.finish_fault: raise self.finish_fault
        return 0

    def refused(self, h, d, r):
        return self.finish(h, d, r)

    def take(self):
        return Custody._prepare_original(self.domain, self.functions,
            path='/private/process.slot', nonce=1, retained=0, execution=65536)


class OriginalInstalledProcessTests(unittest.TestCase):
    def test_same_partial_original_blocks_parent_until_confirmed_cleanup(self):
        f = ProcessFixture(); f.issue = 6
        with self.assertRaises(Error) as caught: f.take()
        p = caught.exception.cleanup_process
        self.assertFalse(caught.exception.unknown)
        self.assertIs(f.domain._installed_process_original, p)
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        f.issue = 0; p.close_unstarted(); p.close_unstarted()
        self.assertTrue(p._closed)
        self.assertIsNone(f.domain._installed_process_original)
        self.assertFalse(f.domain._descriptor.close_attempted)
        f.domain.close_after_stop()
        self.assertTrue(f.domain._closed)

    def test_no_process_refusal_clears_only_extra_original_data(self):
        f = ProcessFixture(); f.issue = 1; f.present = False
        with self.assertRaises(Error) as caught: f.take()
        self.assertFalse(caught.exception.unknown)
        self.assertTrue(caught.exception.cleanup_process._closed)
        self.assertIsNone(f.domain._installed_process_original)
        self.assertFalse(f.domain._closed)

    def test_prepare_response_loss_retains_slot_and_never_reprepares(self):
        f = ProcessFixture(); f.prepare_fault = OSError('lost')
        with self.assertRaises(Error) as caught: f.take()
        p = caught.exception.cleanup_process; before = list(f.events)
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(p._reply.value)
        self.assertIs(f.domain._installed_process_original, p)
        with self.assertRaises(Error): p.close_unstarted()
        with self.assertRaises(ValueError): f.take()
        self.assertEqual(f.events, before)
        self.assertFalse(f.original.host._busy)

    def test_capture_loss_retains_every_original(self):
        f = ProcessFixture(); f.capture_fault = OSError('capture')
        with self.assertRaises(Error) as caught: f.take()
        p = caught.exception.cleanup_process
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(tuple(s.value for s in p._slots()[:5]), (101, 301, 401, 501, 601))

    def test_busy_entry_is_known_before_registration_or_ffi(self):
        f = ProcessFixture(); f.original.host._busy = True
        with self.assertRaises(ValueError): f.take()
        self.assertIsNone(f.domain._installed_process_original)
        self.assertEqual(f.events, [])
        self.assertTrue(f.original.host._busy)
        f.original.host._busy = False
        p = f.take(); p.close_unstarted()

    def test_known_current_refusal_keeps_original_cleanup_available(self):
        f = ProcessFixture(); p = f.take(); f.issue = 5
        with self.assertRaises(Error) as caught: p.current()
        self.assertFalse(caught.exception.unknown)
        self.assertIsNone(p._unknown)
        f.issue = 0; p.close_unstarted()
        self.assertTrue(p._closed)

    def test_lost_spawn_reply_never_resends_or_infers_stop(self):
        f = ProcessFixture(); p = f.take(); f.call_fault = OSError('spawn reply')
        with self.assertRaises(Error): p.spawn()
        before = list(f.events)
        for action in (p.spawn, p.poll_stop, p.retire_stopped, p.close_unstarted):
            with self.assertRaises(Error): action()
        self.assertEqual(f.events, before)
        self.assertFalse(p._closed)
        self.assertIs(f.domain._installed_process_original, p)

    def test_lost_finish_with_null_slots_keeps_parent_fenced(self):
        f = ProcessFixture(); p = f.take(); f.finish_fault = OSError('finish reply')
        with self.assertRaises(Error): p.close_unstarted()
        self.assertTrue(all(s.value is None for s in p._slots()))
        self.assertFalse(p._closed)
        self.assertIs(f.domain._installed_process_original, p)
        before = list(f.events)
        with self.assertRaises(Error): p.close_unstarted()
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        self.assertEqual(f.events, before)

    def test_wrong_operation_is_unknown_and_keeps_original_reply(self):
        f = ProcessFixture(); p = f.take(); f.wrong_operation = 8
        with self.assertRaises(Error) as caught: p.current()
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(p._reply.value)

    def test_private_field_serialization_preserves_empty_value_and_selected_env(self):
        f = ProcessFixture(); p = f.take()
        p.prepare_child('/bin/sh', ('', 'snow\u96ea'), (('LANG', ''),))
        self.assertIn(('child', b'\0snow\xe9\x9b\xaa\0', b'LANG\0\0'), f.events)
        p.close_unstarted()

    def test_copy_foreign_component_and_malformed_fields_have_no_ffi(self):
        f = ProcessFixture(); p = f.take(); before = list(f.events)
        for action in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): action(p)
        for args, env in ((['bad'], ()), (('NUL\0',), ()), ((), (('LANG',),))):
            with self.assertRaises(ValueError): p.prepare_child('/bin/sh', args, env)
        self.assertEqual(f.events, before)
        other = ProcessFixture()
        with self.assertRaises(ValueError):
            Custody._prepare_original(f.domain, other.functions, path='/private/p',nonce=1,retained=0,execution=1)
        self.assertEqual(f.events, before)
        p.close_unstarted()
