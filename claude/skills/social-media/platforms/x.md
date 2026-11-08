# X (Twitter)

Rules come from the open-sourced X ranking code (xai-org/x-algorithm).
Facts and file refs: `x-reference.md` (read it first). Code clone: `~/.claude/social/x-algorithm`.
Account: `~/.claude/social/x-niche.md`. Log: `~/.claude/social/x-log.md`.

## Draft

For each idea write 3 versions with different angles (not small word changes: the feed spreads out
posts with similar meaning). Each version must aim at the high-weight actions:

1. **Copy-link / DM share (+20 / +5):** is it useful or striking enough to send to someone?
   (a checklist, a number, a strong clear opinion, a tool, a before/after).
2. **Reply / quote (+5, +20 from mutuals):** does it invite a real answer? End with a specific
   question or an open claim people want to add to. Not "like if you agree".
3. **Follow (+4):** does it show a clear identity ("this account always gives me X")?
4. **Read to the end (dwell):** first line hooks, the rest pays it off. No filler.
5. **No mute / "not interested" (-58.8 / -52.3):** nothing that feels like bait, rage farming,
   off-topic for the audience, or repeated.

Hard bans (they get posts labelled as spam and dropped for non-followers):
"like/RT if...", "reply X to get Y", follow-for-follow, many hashtags, tagging many accounts,
copy-paste duplicate posts, link shorteners or shady links, AI filler that reads as bot-made.

Format notes: the first post of a thread must stand alone (only one post per conversation is shown).
Video longer than 10 s. Links are fine (no ranker penalty), but put the value in the post itself.

## Score each draft (1-5 each) and show the table

| Share | Reply/quote | Follow | Read-through | Mute risk (5 = none) | Fits niche |

Pick the best; say in one line why.

## Plan

- Space posts: 2nd post by the same author in one feed is x0.625, 3rd x0.44. Prefer 1-3 strong
  posts a day spread over hours over many in a row.
- Post when the audience is awake: the first 2 hours decide the small-account boost
  (likes per view above ~1.5%, needs under 50k followers and an original post).
- After posting: reply to every real reply in the first hour (conversation, and mutual replies
  weigh +20). Reply to mutuals' posts too.
- A post is dead after 48 h in For You. Reuse a winning idea later with a new angle, not a copy.
- Stay in the niche: the model learns who engages with your account. Off-topic posts train it wrong.

## Learn

Keep `~/.claude/social/x-log.md`: date, post, angle, views, likes, replies, reposts, shares, follows gained.
Every 10 posts, compare: which angle got the best replies-per-view and follows-per-view. Write
the finding into `~/.claude/social/x-niche.md` and use it for the next drafts.
