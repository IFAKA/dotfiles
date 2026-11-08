---
name: social-media
description: Share a project on social media (X today; more platforms later). Writes, scores and plans posts from what the project really is, with platform rules from real ranking code. Use in any repo when asked to announce, post, tweet, thread, promote or "share my project" on social media.
---

# social-media

Turn a project into posts that reach people. Works in any repo.

## Where things live
- This skill (rules, shared by all projects): `~/.claude/skills/social-media/`
- Account state (same account across projects): `~/.claude/social/`
  - `<platform>-niche.md`: who the account is, audience, goal, voice
  - `<platform>-log.md`: what was posted and how it did
- Project brief (per repo): `.social/brief.md` in the project root

## Steps
1. **Pick the platform.** Default X. Read `platforms/<platform>.md`. Platforms built: `x`.
   Not built yet: LinkedIn, Reddit, Hacker News, Bluesky. If asked, say "not built yet", then
   write `platforms/<name>.md` from its real rules (research first) and add it to this list.
2. **Account.** If `~/.claude/social/<platform>-niche.md` is missing, ask 5 questions (topic,
   who should read, goal, 3 example posts liked, handle and follower count) and write it.
   Keep the follower count current. If it is under ~500, follow "Starting from zero" below.
3. **Project brief.** If `.social/brief.md` is missing, build it from the repo (README, git log,
   package files, demos/screenshots). Keep it under 25 lines:
   - What it is in one plain sentence. Who it is for.
   - The wow: the most surprising true fact or number (lines, days, fps, KB, speed-up).
   - The proof: demo video/GIF/screenshot path, repo URL, live URL.
   - Honest gaps: what is not done yet.
   - Which niche pillar it fits.
   Never invent numbers; take them from the repo or run it.
4. **Draft, score, plan** with the platform file. Show the score table, pick one, say why.
5. **Media.** Posts with a real demo beat text. If the project can be recorded or screenshotted,
   say which file to attach (or make one). Do not post anything yourself: output text and the
   file path; the user posts it.
6. **Log.** After the user posts, add a row to the platform log; every 10 posts compare angles
   and write the finding into the niche file.

## Starting from zero (under ~500 followers)
Nobody sees a post by default. Almost every viewer is a non-follower, so the post must work for
a stranger with no context.
- Say who you are in the post or profile in plain words; do not assume people know the project.
- Lead with the demo (video/GIF) or one surprising number. A link-only or text-only post dies.
- Spend as much effort on replies to people in the niche as on posts. A good reply to a bigger
  account is how strangers find you. Draft 3 to 5 such replies with every post.
- Post on a steady schedule; do not judge one post. Compare after 10 posts, not 1.
- Do not count likes from friends; do not ask for follows or likes.
- Expect small numbers (single digits to low tens). Report them honestly, never as a failure.

## Rules for all platforms
- Plain, concrete, short. No hype words, no bait, no fake urgency.
- Honest about what is not done.
- One idea per post. Value inside the post, link second.
- Never post, DM or follow for the user.
