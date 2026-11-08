# How the X "For You" feed ranks a post (from the code)

Source: https://github.com/xai-org/x-algorithm, cloned at `~/.claude/social/x-algorithm` (2026-11-02).
All numbers are the defaults in the code. X can change them live with experiments, so treat them
as "true now, re-check later". Re-check with: `git -C ~/.claude/social/x-algorithm pull` and look at the files named below.

## 1. The score

For every viewer, a model (Phoenix) guesses how likely THIS viewer is to do each action on your post.
Score = sum of (weight x guessed chance). Weights: `home-mixer/params/param.rs:402-520`.

| Action the viewer might take | Weight | Meaning for you |
|---|---|---|
| Share by "copy link" | +20 | strongest single signal: make posts people want to send elsewhere |
| Reply | +5 | ask for an answer, not a like |
| Reply, when you and viewer follow each other | +5 +15 = +20 | talk with mutuals; build a mutual circle |
| Quote | +5 | give a take people want to add to |
| Share via DM | +5 | "send this to a friend" content |
| Follow you (from this post) | +4 | show who you are; make the next post worth waiting for |
| Share (other) | +2 | |
| Repost | +1 | |
| Like | +0.66 | weak on its own |
| Click into post / open link | +0.3 / +0.2 | links are not punished by the ranker |
| Click dwell time (seconds on opened post) | +0.4 per unit | long, worth-opening content |
| Dwell, photo expand, quoted click | +0.05 | |
| Mute you | -58.8 | the big danger |
| "Not interested" | -52.3 | the big danger |
| Block you | -31.2 | |
| Report | -234 | rare, but huge |
| Scroll past without stopping | -0.02 | |

Important: the weights multiply the GUESSED chance per viewer, not counts. One report does not
"cancel 468 likes". But a post that makes the wrong people want to mute you scores badly for
everyone similar to them.

## 2. After the score

- **Out-of-network x0.75.** Viewers who do not follow you see your post at 75% score
  (`vm-ranker/params.rs:212`). Your replies and reposts also get x0.75 even for followers.
- **Same author, many posts x1.0, 0.625, 0.44, 0.34 ... down to 0.25** in one feed load
  (`vm-ranker/params.rs:170-186`). Posting 5 times in an hour mostly competes with yourself.
- **Similar posts are spread out** (DPP, `vm-ranker/dpp.rs`): posts whose image+text meaning is
  close to a higher-scored post in the same feed are pushed down. Vary angle and format.
- **Only one post per conversation survives** (`home-mixer/filters/dedup_conversation_filter.rs`).
  A thread competes with its own replies; the best part wins. Put the strongest idea in post 1.

## 3. Small-account boost (cold start)

`home-mixer/scorers/author_cold_start.rs`. One post per feed load is lifted to about position 15 if:
- original post (not reply, not repost),
- you have 50,000 followers or fewer,
- post is under 2 hours old,
- it has under 200 views in home feeds.

Which eligible post wins is a draw where "success" = **likes per home view**. Start guess is 1.5%.
So: in the first 2 hours, a like rate above ~1.5% of views keeps winning that slot.
Here likes DO matter a lot. Post when your audience is awake.

## 4. How posts from non-followers get found

- A post enters the main "out-of-network" index after its **first like**; another at **32 likes**
  (`phoenix-rankall-strato/.../phoenixRankAllCandidateProcessor.strato`). Early likes unlock reach.
- Never indexed for strangers: reposts, community posts, self-replies, NSFW.
- The model does not read raw text. It sees an embedding (meaning) of text+media, your author id,
  post age, and maybe engagement counts. It learns WHO engages with YOUR author id.
  So a consistent topic teaches it the right audience; random topics confuse it.
- Retrieval (Oct 2026) is trained on posts people **read all the way through**.
- Posts older than **48 hours** are never shown in For You (`AgeFilter`).

## 5. Things that remove a post (not just lower it)

Visibility rules, `visibility-filtering/rules/levels.rs`, `grox/flows/ptos/state.py`.
For non-followers, a post is dropped if labelled: spam (high recall), malicious or untrusted URL,
low quality, duplicate content, duplicate mention, "do not amplify", spam reply.
Spam labels the AI classifier (Grox) looks for include:
engagement farming, engagement trading, **engagement baiting**, **hashtag abuse**, **mention abuse**,
scam links, bot-produced, manipulated media, card manipulation.

Account reputation (`agatha/`): blocks, reports and spam reports divided by likes from non-followers.
Many blocks per like slowly labels the account.

Not found in the code: a Premium/verified boost, a hashtag boost, a link penalty, a language penalty.
Video counts as a "quality view" only if it is longer than 10 seconds.
