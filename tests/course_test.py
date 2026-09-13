#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module(name):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CourseStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "Courses"
        self.root.mkdir()
        self.course = self.root / "AI Engineering With Spaces"
        (self.course / "Week 1").mkdir(parents=True)
        (self.course / "Week 1" / "001 Intro.mp4").touch()
        (self.course / "Week 1" / "002 RAG.mp4").touch()
        (self.course / "notes.md").touch()
        self.state_file = Path(self.temp.name) / ".local/state/course/state.json"
        os.environ["COURSE_STATE_FILE"] = str(self.state_file)
        self.course_module = load_module("course")

    def tearDown(self):
        os.environ.pop("COURSE_STATE_FILE", None)
        self.temp.cleanup()

    def test_nested_video_discovery_and_progress(self):
        self.assertEqual([path.name for path in self.course_module.videos(self.course)], ["001 Intro.mp4", "002 RAG.mp4"])
        self.assertEqual(self.course_module.summary(self.course, {"completed": ["Week 1/001 Intro.mp4"]})[:2], (1, 2))

    def test_state_is_atomic_and_invalid_lessons_are_ignored(self):
        state = {"last_course": str(self.course), "courses": {str(self.course): {"current_lesson": "gone.mp4", "completed": ["gone.mp4"]}}}
        self.course_module.save_state(state)
        self.assertEqual(json.loads(self.state_file.read_text())["last_course"], str(self.course))
        self.assertEqual(self.course_module.summary(self.course, state["courses"][str(self.course)])[2], None)

    def test_query_matches_prefix_and_fuzzy(self):
        other = self.root / "Mandarin"
        other.mkdir()
        courses = [self.course, other]
        self.assertEqual(self.course_module.matches(courses, "ai"), [self.course])
        self.assertEqual(self.course_module.matches(courses, "mrin"), [other])


if __name__ == "__main__":
    unittest.main()
