"""Actual Python intake wrapper; explicit scalar Core metadata port, no Host."""
import copy
from dataclasses import FrozenInstanceError
import hashlib
import json
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_project import OriginalLocalProjectConfiguration
from test_local_original_metadata import OriginalMetadataTests


BODY = ('{"connectors":"./connections.json","lock":null,'
        '"mock_answers":[["task:z","./z.yaml"],["task:a","./a.yaml"]],'
        '"mock_data":"./raw.json","model_tasks":"./tasks.json",'
        '"profile":"mock","state_dir":"./state"}')


def wire(body=BODY, *, cid=None):
    return json.dumps({'body': body, 'cid': cid if cid is not None else
                      'sha256:' + hashlib.sha256(body.encode()).hexdigest()}).encode()


class LocalProjectIntakeTests(unittest.TestCase):
    def test_same_original_core_projection_keeps_order_and_source_until_retirement(self):
        core, source, calls, _, _ = OriginalMetadataTests().bridge(kind=5, payload=wire())
        project = OriginalLocalProjectConfiguration(core, source)
        self.assertEqual([name for _, name, _ in calls], ['reserve'])
        locations = project.prepare()
        self.assertIs(project.prepare(), locations)
        self.assertEqual(locations.profile, 'mock')
        self.assertEqual(locations.mock_answers, (('task:z', './z.yaml'), ('task:a', './a.yaml')))
        self.assertEqual(locations.state_dir, './state')
        with self.assertRaises(FrozenInstanceError): locations.profile = 'foreign'
        with self.assertRaises(TypeError): copy.copy(project)
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)
        self.assertIs(core._loans[source.ticket], source)
        self.assertTrue(project.close())
        self.assertIs(core._loans[source.ticket], source)
        with self.assertRaises(ValueError): project.prepare()

    def test_failed_copy_and_cleanup_keep_same_child_without_reprepare(self):
        core, source, calls, codes, _ = OriginalMetadataTests().bridge(kind=5, payload=wire())
        ready = [False]
        project = OriginalLocalProjectConfiguration(core, source)
        core._inputs[project._output.ticket].cleanup = lambda: ready[0]
        codes['produce'] = -31
        with self.assertRaises(LocalCoreError): project.prepare()
        with self.assertRaises(ValueError): project.prepare()
        self.assertFalse(project.close())
        self.assertIs(core._loans[project._output.ticket], project._output)
        self.assertIs(core._loans[source.ticket], source)
        ready[0] = True
        self.assertTrue(project.close())
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)

    def test_foreign_input_and_changed_body_refuse_without_replacement(self):
        core, source, calls, _, _ = OriginalMetadataTests().bridge(kind=5, payload=wire(cid='foreign'))
        with self.assertRaises(ValueError):
            OriginalLocalProjectConfiguration(core, copy.copy(source))
        self.assertEqual(calls, [])
        project = OriginalLocalProjectConfiguration(core, source)
        with self.assertRaises(ValueError): project.prepare()
        with self.assertRaises(ValueError): project.prepare()
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)
        self.assertTrue(project.close())


if __name__ == '__main__':
    unittest.main()
