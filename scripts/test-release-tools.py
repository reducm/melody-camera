#!/usr/bin/env python3
"""发布边界回归：防止不同提交、被替换的文件或错误平台包进入 Release。"""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('prepare_release', Path(__file__).with_name('prepare-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
package_spec = importlib.util.spec_from_file_location('package_release', Path(__file__).with_name('package-release.py'))
package = importlib.util.module_from_spec(package_spec)
package_spec.loader.exec_module(package)


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for sdk in ('iphoneos', 'iphonesimulator'):
            self.fixture(sdk)

    def fixture(self, sdk, prefix=None):
        name = f'MelodyCamera-{sdk}'
        archive = self.output / (name + ('.ipa' if sdk == 'iphoneos' else '.zip'))
        prefix = prefix or ('Payload/MelodyCamera.app/' if sdk == 'iphoneos' else 'MelodyCamera.app/')
        with zipfile.ZipFile(archive, 'w') as package:
            for file in ('Info.plist', 'MelodyCamera', 'Legal/dependencies.json'):
                package.writestr(prefix + file, '固定打包测试数据，非真实应用')
        metadata = {'file': archive.name, 'sdk': sdk, 'commit': 'a' * 40,
                    'source_dirty': False, 'version': '0.1.0', 'build': '3',
                    'configuration': 'Release', 'architecture': 'arm64',
                    'models_included': False, 'api_key_included': False,
                    'runtime_patches': ['drawthings-empty-unused-grpc-server-key-v1'],
                    'bytes': archive.stat().st_size, 'sha256': release.digest(archive)}
        (self.output / (name + '.json')).write_text(json.dumps(metadata))

    def change(self, **values):
        path = self.output / 'MelodyCamera-iphoneos.json'
        metadata = json.loads(path.read_text())
        metadata.update(values)
        path.write_text(json.dumps(metadata))

    def check(self):
        return release.validate_assets(self.output, 'a' * 40, '0.1.0')

    def test_matching_pair_passes(self):
        self.assertEqual(self.check(), '3')

    def test_different_commit_rejected(self):
        self.change(commit='b' * 40)
        with self.assertRaises(ValueError): self.check()

    def test_uncommitted_source_rejected(self):
        self.change(source_dirty=True)
        with self.assertRaises(ValueError): self.check()

    def test_replaced_archive_rejected(self):
        (self.output / 'MelodyCamera-iphoneos.ipa').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.check()

    def test_simulator_disguised_as_ipa_rejected(self):
        self.fixture('iphoneos', prefix='MelodyCamera.app/')
        with self.assertRaises(ValueError): self.check()

    def test_different_builds_rejected(self):
        self.change(build='4')
        with self.assertRaises(ValueError): self.check()

    def test_path_escape_rejected(self):
        self.change(file='../private.ipa')
        with self.assertRaises(ValueError): self.check()

    def test_model_metadata_rejected(self):
        self.change(models_included=True)
        with self.assertRaises(ValueError): self.check()


class CredentialChecks(unittest.TestCase):
    def test_tls_header_constant_is_not_a_private_key(self):
        self.assertFalse(package.has_sensitive_content(io.BytesIO(b'-----BEGIN ' + b'PRIVATE KEY-----\0')))

    def test_pem_with_encoded_body_is_rejected(self):
        data = b'-----BEGIN ' + b'PRIVATE KEY-----\n' + b'A' * 64 + b'\n'
        self.assertTrue(package.has_sensitive_content(io.BytesIO(data)))

    def test_key_across_chunk_boundary_is_rejected(self):
        data = b' ' * (1024 * 1024 - 12) + b'sk' + b'-' + b'a' * 32
        self.assertTrue(package.has_sensitive_content(io.BytesIO(data)))


class RuntimePatchChecks(unittest.TestCase):
    def test_known_resource_is_replaced_and_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            target = checkout / package.runtime.RESOURCE
            target.parent.mkdir(parents=True)
            target.write_bytes(b'upstream fixture')
            target.chmod(0o444)
            with patch.object(package.runtime.subprocess, 'check_output', side_effect=[package.runtime.REVISION, b'upstream fixture'] * 2):
                package.runtime.apply_patch(checkout)
                self.assertEqual(target.read_bytes(), package.runtime.REPLACEMENT)
                package.runtime.apply_patch(checkout)
                self.assertEqual(target.stat().st_mode & 0o777, 0o444)

    def test_changed_revision_rejected(self):
        with patch.object(package.runtime.subprocess, 'check_output', return_value='new-revision'):
            with self.assertRaises(ValueError): package.runtime.apply_patch(Path('/unused'))

    def test_other_modification_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            target = checkout / package.runtime.RESOURCE
            target.parent.mkdir(parents=True)
            target.write_bytes(b'other work')
            with patch.object(package.runtime.subprocess, 'check_output', side_effect=[package.runtime.REVISION, b'original']):
                with self.assertRaises(ValueError): package.runtime.apply_patch(checkout)
            self.assertEqual(target.read_bytes(), b'other work')


if __name__ == '__main__':
    unittest.main()
