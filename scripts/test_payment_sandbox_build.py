#!/usr/bin/env python3
"""Offline regression tests for sandbox-only build generation."""

import base64
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from build_payment_sandbox import generate_configuration, validate_public_config, PRODUCTION_REFERENCE


class SandboxBuildTests(unittest.TestCase):
    project = "abcdefghijklmnopqrst"

    def config(self, **changes):
        value = {"supabase_url": f"https://{self.project}.supabase.co",
                 "supabase_anon_key": "sb_publishable_test_public_key_0123456789", "project_ref": self.project}
        value.update(changes)
        return value

    def jwt(self, role, reference):
        payload = base64.urlsafe_b64encode(json.dumps({"role": role, "ref": reference}).encode()).decode().rstrip("=")
        return f"header.{payload}.signature"

    def test_rejects_production_and_server_credentials(self):
        invalid = [self.config(supabase_url=f"https://{PRODUCTION_REFERENCE}.supabase.co", project_ref=PRODUCTION_REFERENCE),
                   self.config(supabase_anon_key="sb_secret_never-embed-this"),
                   self.config(supabase_anon_key=self.jwt("service_role", self.project)),
                   self.config(supabase_anon_key=self.jwt("anon", "different-project"))]
        for value in invalid:
            with self.subTest(value=list(value)), self.assertRaises(ValueError):
                validate_public_config(value)

    def test_rejects_untrusted_urls_and_non_sandbox_apple_configuration(self):
        for url in ["http://abcdefghijklmnopqrst.supabase.co", "https://example.com",
                    "https://abcdefghijklmnopqrst.supabase.co?token=bad",
                    "https://user:password@abcdefghijklmnopqrst.supabase.co",
                    "https://abcdefghijklmnopqrst.supabase.co:443"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_public_config(self.config(supabase_url=url))
        with self.assertRaises(ValueError):
            validate_public_config(self.config(apple_environment="Production"))
        with self.assertRaises(ValueError):
            validate_public_config(self.config(pro_enabled=True))

    def test_accepts_matching_public_anon_and_publishable_keys(self):
        for key in [self.config()["supabase_anon_key"], self.jwt("anon", self.project)]:
            url, actual_key, project = validate_public_config(self.config(supabase_anon_key=key))
            self.assertEqual(project, self.project)
            self.assertEqual(actual_key, key)
            self.assertEqual(url, f"https://{self.project}.supabase.co")

    def test_generated_build_enables_only_sandbox_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary) / "repository"
            source = repository / "bilu/Info.plist"
            source.parent.mkdir(parents=True)
            original = {"BILUCommerceEnabled": False, "BILUProEnabled": False, "SomeExistingSetting": "preserved"}
            source.write_bytes(plistlib.dumps(original))
            scheme = repository / "bilu.xcodeproj/xcshareddata/xcschemes/bilu.xcscheme"
            scheme.parent.mkdir(parents=True)
            scheme.write_text("<Scheme><LaunchAction/></Scheme>")
            xcconfig, generated, _ = generate_configuration(self.config(), Path(temporary) / "build", repository)
            output = plistlib.loads(generated.read_bytes())
            self.assertTrue(output["BILUCommerceEnabled"])
            self.assertFalse(output["BILUProEnabled"])
            self.assertTrue(output["BILUPaymentSandbox"])
            self.assertEqual(output["SomeExistingSetting"], "preserved")
            self.assertEqual(plistlib.loads(source.read_bytes()), original)
            self.assertIn("[config=Debug]", xcconfig.read_text())
            self.assertIn("BILU_PAYMENT_INFO_biluShare = $(SRCROOT)/biluShare/Info.plist", xcconfig.read_text())
            scheme.write_text('<Scheme><LaunchAction><StoreKitConfigurationFileReference identifier="Local.storekit"/></LaunchAction></Scheme>')
            with self.assertRaises(ValueError):
                generate_configuration(self.config(), Path(temporary) / "second-build", repository)


if __name__ == "__main__":
    unittest.main()
