#!/usr/bin/env python3
import importlib.machinery, importlib.util, json, os, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def load_module(name):
    loader = importlib.machinery.SourceFileLoader(name, str(ROOT / "bin" / name)); spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

class CourseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name) / "Courses"; self.root.mkdir()
        self.course = self.root / "AI ® With Spaces"; (self.course / "Week 1").mkdir(parents=True)
        for name in ("002 RAG.mp4", "001 Intro.mp4"): (self.course / "Week 1" / name).touch()
        (self.course / "BONUSES").mkdir(); (self.course / "BONUSES" / "070 Bonus.mp4").touch(); (self.course / "notes.md").touch()
        self.state_file = Path(self.temp.name) / ".local/state/course/state.json"; os.environ["COURSE_STATE_FILE"] = str(self.state_file)
        self.course_module, self.play_module = load_module("course"), load_module("course-play")
    def tearDown(self): os.environ.pop("COURSE_STATE_FILE", None); self.temp.cleanup()
    def test_recursive_discovery_and_natural_playlist_order(self):
        self.assertEqual({p.name for p in self.course_module.videos(self.course)}, {"001 Intro.mp4", "002 RAG.mp4", "070 Bonus.mp4"})
        self.assertEqual([p.name for p in self.play_module.playlist(self.course)], ["001 Intro.mp4", "002 RAG.mp4", "070 Bonus.mp4"])
    def test_manifest_order_including_unprefixed_setup_videos(self):
        (self.course / "names.txt").write_text("002 RAG\nSetup\n001 Intro\n", encoding="utf-8")
        (self.course / "Setup.mp4").touch()
        self.assertEqual([p.name for p in self.play_module.playlist(self.course)], ["002 RAG.mp4", "Setup.mp4", "001 Intro.mp4", "070 Bonus.mp4"])
    def test_state_atomic_pruned_and_queries(self):
        other = self.root / "Mandarin"; other.mkdir()
        state = {"last_course": str(other.resolve()), "courses": {str(self.course.resolve()): {"current_lesson":"gone.mp4", "completed":["gone.mp4"]}, str(other.resolve()): {}}}
        self.course_module.save_state(state); loaded = json.loads(self.state_file.read_text()); self.course_module.clean_state(loaded, [self.course])
        self.assertNotIn(str(other.resolve()), loaded["courses"]); self.assertEqual(self.course_module.summary(self.course, loaded["courses"][str(self.course.resolve())])[::2], (0, None))
        self.assertEqual(self.course_module.matches([self.course, other], "ai"), [self.course]); self.assertEqual(self.course_module.matches([self.course, other], "mrin"), [other])
    def test_completion_threshold(self):
        data = {}; self.play_module.record_completion(data, "001 Intro.mp4", 100, 91, 9); self.assertNotIn("001 Intro.mp4", data.get("completed", []))
        self.play_module.record_completion(data, "001 Intro.mp4", 100, 91, 10); self.assertIn("001 Intro.mp4", data["completed"])
    def test_empty_course_has_zero_progress(self):
        empty = self.root / "Empty"; empty.mkdir(); self.assertEqual(self.course_module.summary(empty, {})[:2], (0, 0))
if __name__ == "__main__": unittest.main()
