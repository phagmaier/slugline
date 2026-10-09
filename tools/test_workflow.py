"""Fast checks for task status and test selection; no app builds or GUI required."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import check_docs

ROOT = Path(__file__).resolve().parent.parent


class BacklogStatusTests(unittest.TestCase):
    def test_status_matches_result(self):
        cases = [
            ("x", "", False),
            (" ", "", False),
            ("x", "_open_", False),
            (" ", "Fixed; focused checks passed.", False),
            (" ", "_open_ — partial; the remaining behavior is blocked.", True),
            ("x", "Fixed; focused checks passed; commit pending.", True),
        ]
        for ticked, result, valid in cases:
            with self.subTest(ticked=ticked, result=result):
                check_docs.problems.clear()
                check_docs.warnings.clear()
                text = (
                    f"- [{ticked}] [B1](#b1) Example\n\n"
                    '<a id="b1"></a>\n### B1 — Example\n\n'
                    f"**Result:** {result}\n\n"
                )
                check_docs.backlog(text)
                self.assertEqual(not check_docs.problems, valid)
                self.assertEqual(check_docs.warnings, [])

    def test_all_scoped_crate_guides_are_checked(self):
        for path in ROOT.glob("crates/*/AGENTS.md"):
            self.assertIn(str(path.relative_to(ROOT)), check_docs.DOCS)


class AgentCommandTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="slugline-workflow-")
        self.addCleanup(self.scratch.cleanup)
        self.bin = Path(self.scratch.name)
        # Restrict PATH so installed PDF tools cannot hide a missing prerequisite.
        for command in ("bash", "dirname", "find", "wc", "sed"):
            (self.bin / command).symlink_to(shutil.which(command))
        self.env = dict(os.environ, PATH=str(self.bin))
        output = (
            "import json, os, sys\n"
            "print(json.dumps({'cwd': os.getcwd(), 'args': sys.argv[1:]}))\n"
            "sys.exit(int(os.environ.get('FAKE_TEST_EXIT', '0')))\n"
        )
        self.stub("flutter", output)
        self.stub("cargo", output)
        self.stub(
            "xvfb-run",
            "import os, sys\nassert sys.argv[1] == '-a'\n"
            "os.execvp(sys.argv[2], sys.argv[2:])\n",
        )

    def stub(self, name, source):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n{source}", encoding="utf-8")
        path.chmod(0o755)

    def run_agent(self, *args):
        return subprocess.run(
            [str(ROOT / "tools/agent.sh"), *args],
            cwd=self.bin,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )

    @staticmethod
    def calls(result):
        return [
            json.loads(line)
            for line in result.stdout.splitlines()
            if line.startswith("{")
        ]

    def test_quick_forwards_exact_filter_from_outside_repo(self):
        args = [
            "--test", "incremental_differential", "a filter with spaces", "--", "--exact"
        ]
        result = self.run_agent("quick", "layout", *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {"cwd": str(ROOT), "args": ["test", "-p", "slugline_layout", *args]}
        self.assertEqual(self.calls(result), [expected])

    def test_native_selects_only_requested_suite_and_filter(self):
        for suite in ("writing", "writing_test.dart", "integration_test/writing_test.dart"):
            with self.subTest(suite=suite):
                result = self.run_agent("native", suite, "--plain-name", "a test name")
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = {
                    "cwd": str(ROOT / "app"),
                    "args": [
                        "test", "integration_test/writing_test.dart", "-d", "linux",
                        "--plain-name", "a test name",
                    ],
                }
                self.assertEqual(self.calls(result), [expected])

    def test_only_export_requires_pdf_tools(self):
        result = self.run_agent("native", "export")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required command not found: pdftotext", result.stderr)
        self.assertEqual(self.calls(result), [])
        for tool in ("pdftotext", "pdftohtml"):
            self.stub(tool, "")
        result = self.run_agent("native", "export")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls(result)), 1)

    def test_listing_and_invalid_selection_do_not_run_tests(self):
        (self.bin / "flutter").unlink()
        listed = self.run_agent("native", "--list")
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(len(listed.stdout.splitlines()), 7)
        self.assertIn("writing", listed.stdout.splitlines())
        for args in (("native", "typo"), ("native",), ("quick", "typo")):
            with self.subTest(args=args):
                result = self.run_agent(*args)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(self.calls(result), [])
        help_result = self.run_agent("help")
        self.assertEqual(help_result.returncode, 0)
        self.assertNotIn("pipefail", help_result.stdout)

    def test_full_native_mode_stops_on_first_failure(self):
        for tool in ("pdftotext", "pdftohtml"):
            self.stub(tool, "")
        command = [str(ROOT / "tools/test_linux_integration.sh")]
        result = subprocess.run(
            command, cwd=self.bin, env=self.env, capture_output=True,
            text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls(result)), 7)
        self.env["FAKE_TEST_EXIT"] = "7"
        result = subprocess.run(
            command, cwd=self.bin, env=self.env, capture_output=True,
            text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(len(self.calls(result)), 1)


if __name__ == "__main__":
    unittest.main()
