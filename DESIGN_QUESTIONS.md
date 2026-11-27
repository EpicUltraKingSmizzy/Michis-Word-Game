# Michi's Word Game design questions

These are the non-coding questions that came up while building features for Michi's Word Game. Each one has the answer I picked and a one-line reason. Change any answer you like and the code will follow.

The numbers for the missed-words page live in `MissedWordsTuning` (lib/logic/missed_words.dart). The page itself is the `missed` stage in lib/ui/screens/results_screen.dart.

## A. End-of-game missed words

1. **Which games show the missed words?** Only a completed solo round: you opened a room and started the game with nobody else in it. Multiplayer rooms and challenge links don't show it. *Why:* you asked for it after a Solo Game, and in a group it would mean showing words nobody found, which is a different feature.
2. **What about a round that was quit early?** It never shows. Quitting goes straight home and skips the results screen entirely, so only a round that ran to the buzzer gets there. *Why:* it's a reward for finishing, and a quit round isn't scored.
3. **Where in the end-of-game flow does it appear?** Right after the word-by-word scoring and the final score (after you tap past it), and before the highlights, the longest word and the winner pages. *Why:* that's where you said it should go, after the found words and the points.
4. **What happens if I press Skip during scoring?** Skip still only skips the scoring animation. The missed-words page still shows and waits for your tap, like the other pages. *Why:* that matches how Skip already works for the highlights and the longest word.
5. **What counts as a missed word?** Any word the game's solver finds on the board (using the round's minimum word length) that isn't in your list of found words. *Why:* that's the same word list the scoring and the "words hiding in this grid" count use, so it can't disagree with them.
6. **How many words are shown?** Up to 10 (`MissedWordsTuning.count`). *Why:* the number you asked for, and 10 pills fit on a phone screen without scrolling.
7. **Which lengths come first?** Words of 3 to 5 letters (`MissedWordsTuning.shortMin` and `shortMax`). If the round's minimum length is 4 or 5, the shorter ones simply don't exist on the board. *Why:* these are the everyday words a player is most likely to kick themselves over.
8. **How are the 10 picked when there are more than 10 short missed words?** At random, but the random pick is seeded by the board's letters, so the same board always shows the same list. *Why:* random keeps it from always showing words starting with A, and the seed keeps the page from changing if it's rebuilt.
9. **What if there are fewer than 10 short missed words?** The rest are filled with longer missed words, shortest first (random within the same length). *Why:* the next-easiest words are the most useful ones to see.
10. **What if I found every 3-5 letter word?** The page shows longer words you missed instead, and Michi says "You found every short word! Here are some longer ones you missed:". *Why:* that's what you asked for, and the message gives you credit for clearing the short words.
11. **How is the longest word kept out?** Every word that ties for the longest length on the board is left out, which is exactly the list the longest-word page reveals from (`pickLongestWord` / `allLongest`). *Why:* the longest word has its own reveal, and with a tie the reveal can show any of them, so none of them are spoiled early.
12. **What if fewer than 10 words are left after all that?** It shows however many there are, and the wording changes to "Here is a word you missed" for just one. *Why:* a short honest list is better than padding it with the longest word.
13. **What if there are no missed words at all?** The page is skipped and you go straight to the highlights. *Why:* an empty page would be a pointless extra tap.
14. **What order are the shown words in?** By length, shortest first, then alphabetical. *Why:* it reads like the list of rules (3 letters = 1 point, and so on) and makes the longer ones stand out at the end.
15. **How does the page look?** Michi's speech bubble at the top, then each word as a rounded pill (cyan for 3-5 letters, gold for longer ones) with what it would have scored beside it, for example `+2`. The pills pop in one after another with the same bounce the highlights use. *Why:* it reuses the existing pills, colors and animation, so it feels like part of the same results screen.
16. **What score is shown next to each word?** What it would have earned you in that solo round: the normal points (3 letters = 1, +1 per extra letter), doubled because every word in a solo round is unique. *Why:* that matches the "+N" you saw for your own words during scoring.
17. **Can I tap a missed word to see it on the board?** Not in this version. A tap anywhere moves on to the next page, as on the other results pages. *Why:* it keeps the tap-to-continue flow simple. Tracing each word on the board could come later.
18. **Are odd dictionary words (place names and so on) filtered out here?** No, it uses the dictionary as it is. *Why:* the dictionary is being cleaned up separately, and once that lands this page gets the benefit automatically.
