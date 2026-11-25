"""Tests for the studydash collector's pure logic.

Run from the repo root:  python3 -m unittest discover -s tests
The script has no .py suffix, so it is loaded by path. Nothing here touches
~/.local/state or ~/.config: every test passes data in, or uses a temp dir.
"""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "studydash")


def load():
    loader = importlib.machinery.SourceFileLoader("studydash", SCRIPT)
    spec = importlib.util.spec_from_loader("studydash", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def session(start, end):
    return {"start": start, "end": end}


class Base(unittest.TestCase):
    def setUp(self):
        # A fresh module per test, so apply_config() in one test cannot leak
        # settings into the next.
        self.m = load()
        self.m.TARGET_DATE = date(2026, 12, 15)
        self.m.COURSE_NAME = "Test course"


class Course(Base):
    def test_unknown_with_a_single_point(self):
        out = self.m.build_course([{"date": "2026-11-20", "percent": 50}], date(2026, 11, 25))
        self.assertEqual(out["status"], "unknown")
        self.assertIsNone(out["percent_per_week_actual"])

    def test_behind_when_actual_is_under_required(self):
        # 5%/wk actual; 30% left over 3 weeks needs 10%/wk.
        rows = [{"date": "2026-11-10", "percent": 60}, {"date": "2026-11-24", "percent": 70}]
        out = self.m.build_course(rows, date(2026, 11, 24))
        self.assertEqual(out["percent_per_week_actual"], 5.0)
        self.assertEqual(out["status"], "behind")

    def test_past_deadline_with_recent_progress_is_behind(self):
        rows = [{"date": "2026-12-10", "percent": 80}, {"date": "2026-12-19", "percent": 95}]
        out = self.m.build_course(rows, date(2026, 12, 20))
        self.assertEqual(out["status"], "behind")
        self.assertEqual(out["days_remaining"], -5)
        self.assertIsNone(out["percent_per_week_required"])

    def test_finished_is_ahead_even_past_deadline(self):
        rows = [{"date": "2026-12-10", "percent": 100}]
        self.assertEqual(self.m.build_course(rows, date(2026, 12, 20))["status"], "ahead")

    def test_stale_progress_is_behind(self):
        rows = [{"date": "2026-10-01", "percent": 40}, {"date": "2026-11-01", "percent": 90}]
        self.assertEqual(self.m.build_course(rows, date(2026, 11, 20))["status"], "behind")

    def test_pace_window_anchors_on_value_when_it_opened(self):
        # 50% held from 10-01; inside the window only one point. The baseline
        # is 50% at the window's opening day, so the gap counts against pace.
        ref = date(2026, 11, 28)
        rows = [{"date": "2026-10-01", "percent": 50}, {"date": "2026-11-28", "percent": 58}]
        out = self.m.build_course(rows, ref)
        self.assertEqual(out["percent_per_week_actual"], 2.0)   # 8% over 4 weeks


class Hours(Base):
    def test_sub_minute_sessions_are_ignored(self):
        rows = [session("2026-11-24T10:00:00+01:00", "2026-11-24T10:00:30+01:00"),
                session("2026-11-24T11:00:00+01:00", "2026-11-24T12:00:00+01:00")]
        out, _ = self.m.build_hours(rows, date(2026, 11, 25))
        self.assertEqual(out["weeks"][-1]["hours"], 1.0)

    def test_long_session_is_capped_and_reported(self):
        rows = [session("2026-11-24T00:00:00+01:00", "2026-11-24T10:00:00+01:00")]
        out, truncated = self.m.build_hours(rows, date(2026, 11, 25))
        self.assertEqual(out["weeks"][-1]["hours"], 4.0)
        self.assertEqual(out["truncated_count"], 1)
        self.assertEqual(truncated[0]["real_hours"], 10.0)


class Revision(Base):
    def test_first_review_is_due_after_completion(self):
        rows = [{"room": "A", "completed": "2026-11-01", "reviews": []}]
        due = self.m.build_revision(rows, date(2026, 11, 10))["due"]
        self.assertEqual(due, [{"room": "A", "interval": "7d", "overdue_days": 2}])

    def test_late_review_pushes_the_next_one_out(self):
        # The 7d review was done 50 days late; the 30d one runs from it.
        rows = [{"room": "A", "completed": "2026-09-01", "reviews": ["2026-10-28"]}]
        self.assertEqual(self.m.build_revision(rows, date(2026, 11, 25))["due"], [])
        due = self.m.build_revision(rows, date(2026, 11, 30))["due"]
        self.assertEqual(due, [{"room": "A", "interval": "30d", "overdue_days": 3}])

    def test_reviews_union_across_lines(self):
        rows = [{"room": "A", "completed": "2026-09-01", "reviews": []},
                {"room": "A", "completed": "2026-09-01", "reviews": ["2026-09-08"]}]
        self.assertEqual(self.m.fold_rooms(rows)["A"]["reviews"], [date(2026, 9, 8)])

    def test_resolve_room(self):
        folded = self.m.fold_rooms([{"room": n, "completed": "2026-09-01"} for n in
                                    ("Wireshark: The Basics", "Windows 1", "Windows 2")])
        self.assertEqual(self.m.resolve_room("wire", folded), "Wireshark: The Basics")
        self.assertEqual(self.m.resolve_room("Windows 2", folded), "Windows 2")
        self.assertIsNone(self.m.resolve_room("windows", folded))   # ambiguous
        self.assertIsNone(self.m.resolve_room("nope", folded))


class Config(unittest.TestCase):
    def setUp(self):
        self.m = load()
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "config.toml")

    def tearDown(self):
        self.dir.cleanup()

    def write(self, text):
        with open(self.path, "w") as fh:
            fh.write(text)

    def test_missing_file_is_unconfigured(self):
        self.assertEqual(self.m.load_config(self.path), {})
        self.assertFalse(self.m.is_configured())

    def test_values_apply(self):
        self.write('[course]\nname = "X"\ntarget_date = 2027-01-31\nweekly_hours = 3\n'
                   '[review]\nintervals = [3, 10]\n[load]\nscan_roots = ["~/code"]\n')
        self.m.apply_config(self.m.load_config(self.path))
        self.assertTrue(self.m.is_configured())
        self.assertEqual(self.m.TARGET_DATE, date(2027, 1, 31))
        self.assertEqual(self.m.TARGET_WEEKLY_HOURS, 3.0)
        self.assertEqual(self.m.REVIEW_INTERVALS, [3, 10])
        self.assertEqual(self.m.SCAN_ROOTS, [os.path.expanduser("~/code")])

    def test_quoted_date_also_works(self):
        self.write('[course]\ntarget_date = "2027-01-31"\n')
        self.m.apply_config(self.m.load_config(self.path))
        self.assertEqual(self.m.TARGET_DATE, date(2027, 1, 31))

    def test_bad_and_unknown_values_fall_back(self):
        self.write('[course]\nweekly_hours = -2\ncolour = "red"\n'
                   '[review]\nintervals = []\n')
        values = self.m.load_config(self.path)
        self.assertEqual(values, {})
        self.assertEqual(self.m.TARGET_WEEKLY_HOURS, 5.0)

    def test_broken_toml_is_not_fatal(self):
        self.write('[course\nname = ')
        self.assertEqual(self.m.load_config(self.path), {})

    def test_written_template_reads_back(self):
        self.write(self.m.config_text('Quote "me"', date(2027, 2, 1), 4.5))
        self.m.apply_config(self.m.load_config(self.path))
        self.assertEqual(self.m.COURSE_NAME, 'Quote "me"')
        self.assertEqual(self.m.TARGET_DATE, date(2027, 2, 1))
        self.assertEqual(self.m.TARGET_WEEKLY_HOURS, 4.5)


class Collect(unittest.TestCase):
    def setUp(self):
        self.m = load()
        self.dir = tempfile.TemporaryDirectory()
        state = self.dir.name
        for name in ("STATE",):
            setattr(self.m, name, state)
        for name, fname in (("PROGRESS", "progress.jsonl"), ("SESSIONS", "sessions.jsonl"),
                            ("ROOMS", "rooms.jsonl"), ("STATS", "stats.json")):
            setattr(self.m, name, os.path.join(state, fname))

    def tearDown(self):
        self.dir.cleanup()

    def test_unconfigured_has_no_course_and_no_load(self):
        stats, _ = self.m.collect()
        self.assertFalse(stats["configured"])
        self.assertIsNone(stats["course"])
        self.assertIsNone(stats["load"])
        self.assertIn("stale_after", stats)
        self.assertEqual(stats["sessions"]["nudge_minutes"], 180)

    def test_configured_with_no_data(self):
        self.m.TARGET_DATE = date(2027, 1, 1)
        stats, _ = self.m.collect()
        self.assertTrue(stats["configured"])
        self.assertEqual(stats["course"]["percent"], 0)
        self.assertEqual(stats["course"]["status"], "unknown")


if __name__ == "__main__":
    unittest.main()
