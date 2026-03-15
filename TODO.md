- marks. I need to think more about marks and qfix lists. When items get shifted around
  i want the qfix list to stay as true as possible. so every time one opens, we should
  recreate exactly what are the items based on some marks.
  - tracking will have to store marks and make them easy to delete based on
    request.
  - also some impliciation on deserialization. we will need to make sure we keep
    track of marks after deserialization

- filtering in `open`
  select input windows should also have a filter and a set of keys that can be set that trigger the filter.

select { filter_keymap = { <key> = {desc = <desc>, cb = fun(x: str_items[]) -> number[] ... end } }

that means that we cna filter out and return back the indices of the items we wish to keep

that means when one of these are pressed, we need to

we must also keep track of the total original items as well. and must make the filters into kepmap items too

- for vibe coding, i would like a way not only to transfer to a spot to review the
  code, but to toggle the diff view of the current item i am on. This means
  tracking is going to have to have an idea of "active" such that i cannot imagine what you are
  toggling, but instead have concrete idea of what needs to be toggled when i press
  toggle_diff()
  - this should inline display the diff, i do not know the best way to make this
    happen, but it should use git diff as the primary means to calculate the diff
    and more importantly it should just show the hunk that my cursor intersects.

  - i am afraid it may be a generalized library...

- vibe and search sessions. we sometimes need to call a session and ask for a follow up about what happpened for more changes.
- how to get that?
- opencode run --format json --agent build -m openai/gpt-5.3-codex "your prompt" > /tmp/opencode.jsonl
- SESSION_ID=$(jq -r 'select(.sessionID != null) | .sessionID' /tmp/opencode.jsonl | head -n1)
- opencode run --session "$SESSION_ID" --agent build -m openai/gpt-5.3-codex "follow-up prompt"

```bash
Yes — that is exactly what opencode serve is for.
- Run one long-lived headless server process.
- Send many opencode run requests to it via --attach.
- Keep using the same sessionID with --session for follow-ups.
# 1) Start persistent headless server (once)
export OPENCODE_SERVER_PASSWORD='change-me'
opencode serve --hostname 127.0.0.1 --port 4096
# 2) First query (machine-readable)
opencode run --attach http://127.0.0.1:4096 --format json "first prompt"
# JSON events include: "sessionID":"ses_..."
# 3) Follow-up on same conversation
opencode run --attach http://127.0.0.1:4096 --session ses_... --format json "follow-up prompt"
Notes:
- --continue works too (uses most recent session), but --session is safest for automation.
- If you want interactive rejoin, use opencode attach http://127.0.0.1:4096 --session ses_....
- Set OPENCODE_SERVER_PASSWORD (otherwise server is unsecured).
```

- if there is an active window, that is not a status window, open, then results should not be opened until that is closed.
- we need effetively an action queue along with window lifecycle functions
- i need a way to pring up past vibe sessions that were failed or cancelled so i can use that text again.
- i think something like, if last version of this command executed was a failure / cancel, just auto fill previous text
- make \_99_state persistent that way i dont lose my shit.
- when prompting or searching and a result comes in, the popup became broken with
  quickfix results... Not sure what the issue is if its a me issue or something else
- Prompt should generate its prompt via prompt() instead of passing it into the provider as a string...
- Search Items should be editable. That way i can mark them off as finished
  - use capture input style to "mark" them as done. [x] as done, or delete line
  - this should mean that when we revive the work menu list, it reflects the new reality
- Search item navigation. We should just be able to next("search") to navigate the searches
- tutorials, searches, and visuals should all have their own history
- clean history should be on a vertical as well
- state of state
- maybe this needs to be persisted as json in a tmp file such that we can restore it upon opening. I could see this being super useful
- some sort of interface that i can peruse the types of requests made
- filter by type
- display all
- enter opens up the request
- delete removes the request from history
- search qfix notes should be added as marks
- there will be a need for smarter mark management.
- add an add_data method to context in which when you set the data it:
- asserts if you included a type
- initialized with the proper type
- adds the fields one at a time
- worktrees: I feel that i could turn a lot of this into a work tree way
- this would effectively make it so that running a bunch of parallel requests and changes do not have to become completely ruined, but instead we have everything mergeable and resolveable. I think that this could "be the future" of this plugin

### Unplanned for now, but interesting to think about as things improve

or my skill set improves...

- Vibe Work
- takes the search results and asks the AI to implement those changes.
- this should use the new "vibe" interface i want to make
- something i have ran into, maybe its useful, but being able to do the following
  - search -> partial select -> vibe
- vibe interface
- makes changes, and then describes each edit in a tmp file such that it can be loaded into memory and transfered to quickfixlist
- be able to have a diff view? live view toggle?
