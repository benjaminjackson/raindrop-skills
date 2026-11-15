---
name: raindrop
description: Read and manage the user's Raindrop.io bookmarks through the Raindrop REST API. Use whenever the user mentions Raindrop, bookmarks, saved links, "what did I save about X", tags on saved links, highlights, or reading lists, or asks to save, tag, move, search, export, import, back up or clean up bookmarks. Covers every documented endpoint: bookmarks (called raindrops), collections, sharing, tags, highlights, filters, user, import, export, backups, file uploads and OAuth tokens.
---

# Raindrop

The user's bookmarks live in Raindrop.io. The API calls a bookmark a "raindrop".

## How to call the API

Always use the helper script `scripts/raindrop.sh`, in this skill's base directory. It finds the access token itself and sends it as a bearer token, so the token never enters the conversation. Never print the token, never `cat` a file that holds it, and never paste it into a command.

The script looks for `RAINDROP_API_TOKEN` in the environment, then in a `.env` file in the current directory, then in `~/.config/raindrop/credentials`. If it reports that the token is not set, stop and show the user the "Set up the token" steps in this plugin's README. Do not ask the user to paste the token into the chat.

```bash
scripts/raindrop.sh METHOD PATH                       # no body
scripts/raindrop.sh METHOD PATH 'JSON_BODY'           # JSON body
scripts/raindrop.sh METHOD PATH -                     # JSON body from standard input
scripts/raindrop.sh METHOD PATH --form KEY=VALUE ...  # multipart upload; KEY=@FILE sends a file
```

- `PATH` is everything after `https://api.raindrop.io/rest/v1`, with the query string included. Quote it, because `&` and `?` mean something to the shell.
- For a long JSON body, pass `-` and feed the body in with a heredoc.
- Pipe the output through `jq` to keep only the fields you need. A full bookmark object is large.
- Every response has `"result": true` or `false`. On `false`, read `errorMessage`.

Examples (replace `scripts/raindrop.sh` with the script's full path):

```bash
# The 50 newest bookmarks: date saved, ID, title, link
scripts/raindrop.sh GET '/raindrops/0?perpage=50&sort=-created' \
  | jq -r '.items[] | "\(.created[0:10])\t\(._id)\t\(.title)\t\(.link)"'

# Count the bookmarks that have a tag
scripts/raindrop.sh GET '/raindrops/0?search=%23ai&perpage=1' | jq '.count'

# Save a new bookmark and let Raindrop fetch its title and cover
scripts/raindrop.sh POST /raindrop '{"link":"https://example.com","tags":["to-read"],"pleaseParse":{}}'

# Upload a PDF as a bookmark in collection 12345
scripts/raindrop.sh PUT /raindrop/file --form file=@report.pdf --form collectionId=12345

# Export every bookmark as CSV
scripts/raindrop.sh GET /raindrops/0/export.csv > bookmarks.csv
```

## Things to know

- **System collection IDs:** `0` means all bookmarks except Trash. `-1` is Unsorted. `-99` is Trash. The bulk update and bulk delete endpoints do not accept `0`; give a real collection ID or `-1`.
- **Paging:** `perpage` is 50 at most. `page` starts at 0. The response field `count` is the total number of matches, so loop over pages until you have `count` items.
- **Sort values:** `-created` (newest first, the default), `created`, `score` (relevance, only with `search`), `-sort` (manual order), `title`, `-title`, `domain`, `-domain`.
- **Search:** the `search` value is the same text the user would type in the Raindrop search box. `#tag` finds a tag. URL-encode it in the query string (`#` becomes `%23`, a space becomes `%20`). The full list of search operators is at help.raindrop.io/using-search. When unsure about an operator, test it with a small `perpage` first.
- **Nested collections:** add `nested=true` to include bookmarks from child collections.
- **Rate limit:** 120 requests a minute. For bulk work, use the bulk endpoints instead of one call per bookmark.
- **Reading fields:** use only the documented fields (`_id`, `link`, `title`, `excerpt`, `note`, `type`, `tags`, `cover`, `collection.$id`, `created`, `lastUpdate`, `important`, `highlights`, `domain`). Raindrop says other fields in responses can change without notice.

## Ask before changing anything

Reads need no approval. Before any call that changes or deletes data, tell the user what it will do and how many bookmarks it touches, and wait for a yes. That covers every `POST`, `PUT` and `DELETE`. Take extra care with these, because they cannot be undone from the API:

- `DELETE /collection/-99` empties the Trash.
- `DELETE /raindrops/{collectionId}` with no `ids` and no `search` deletes every bookmark in that collection.
- `PUT /collections/merge`, `PUT /collections/clean`, and `DELETE /tags/{collectionId}`.
- `PUT /raindrops/{collectionId}` with `"tags": []` removes all tags from every bookmark it matches.

## Endpoints

All paths are relative to `https://api.raindrop.io/rest/v1`. Full docs for each group: `https://developer.raindrop.io/v1/<page>.md` (for example `raindrops/multiple.md`).

### Bookmarks, one at a time (`raindrops/single`)

| Method | Path | What it does |
|---|---|---|
| GET | `/raindrop/{id}` | Get one bookmark, including its highlights |
| POST | `/raindrop` | Create a bookmark. Body: `link` (required), plus `title`, `excerpt`, `note`, `tags`, `collection: {"$id": N}`, `important`, `cover`, `type`, `highlights`, `reminder`, `order`. Add `"pleaseParse": {}` to have Raindrop fetch the title, cover and description |
| PUT | `/raindrop/{id}` | Update a bookmark. Same fields as create. `"pleaseParse": {}` re-fetches the page details |
| DELETE | `/raindrop/{id}` | Move a bookmark to Trash. Deleting one already in Trash removes it for good |
| PUT | `/raindrop/file` | Upload a file as a new bookmark (`--form file=@PATH --form collectionId=N`) |
| PUT | `/raindrop/{id}/cover` | Upload a cover image, PNG, GIF or JPEG (`--form cover=@PATH`) |
| GET | `/raindrop/{id}/cache` | Get the permanent copy of the page (Pro accounts only) |
| POST | `/raindrop/suggest` | Suggest a collection and tags for a new link. Body: `{"link": "..."}` |
| GET | `/raindrop/{id}/suggest` | Suggest a collection and tags for an existing bookmark |

### Bookmarks, many at once (`raindrops/multiple`)

| Method | Path | What it does |
|---|---|---|
| GET | `/raindrops/{collectionId}` | List bookmarks. Query: `search`, `sort`, `page`, `perpage`, `nested` |
| POST | `/raindrops` | Create up to 100 bookmarks. Body: `{"items": [ ...bookmark objects... ]}` |
| PUT | `/raindrops/{collectionId}` | Update every bookmark that matches. Pick them with `ids` in the body or `search` in the query. Body fields: `important`, `tags` (appends; `[]` clears all), `media`, `cover`, `collection: {"$id": N}` (moves them) |
| DELETE | `/raindrops/{collectionId}` | Delete every bookmark that matches `ids` (body) or `search` (query). Moves them to Trash; run it on `-99` to delete for good |

### Collections (`collections/methods`, `collections/sharing`, `collections/covers-icons`)

| Method | Path | What it does |
|---|---|---|
| GET | `/collections` | Root collections |
| GET | `/collections/childrens` | Child collections (each has `parent.$id`) |
| GET | `/collection/{id}` | One collection |
| POST | `/collection` | Create. Body: `title`, `view`, `sort`, `public`, `parent: {"$id": N}`, `cover` |
| PUT | `/collection/{id}` | Update. Same fields, plus `expanded` |
| PUT | `/collection/{id}/cover` | Upload a cover image, PNG, GIF or JPEG (`--form cover=@PATH`) |
| DELETE | `/collection/{id}` | Delete a collection and its child collections. Its bookmarks go to Trash |
| DELETE | `/collections` | Delete several. Body: `{"ids": [...]}` |
| PUT | `/collections` | Reorder all (`{"sort": "title"}`, `"-title"` or `"-count"`) or expand or collapse all (`{"expanded": true}`) |
| PUT | `/collections/merge` | Merge collections. Body: `{"to": N, "ids": [...]}` |
| PUT | `/collections/clean` | Delete every empty collection |
| DELETE | `/collection/-99` | Empty the Trash |
| GET | `/user/stats` | Bookmark counts for the system collections |
| POST | `/collection/{id}/sharing` | Invite people. Body: `role` (`member` or `viewer`), `emails` |
| GET | `/collection/{id}/sharing` | List collaborators |
| DELETE | `/collection/{id}/sharing` | Unshare (owner) or leave (collaborator) |
| PUT | `/collection/{id}/sharing/{userId}` | Change a collaborator's role. Body: `{"role": "..."}` |
| DELETE | `/collection/{id}/sharing/{userId}` | Remove a collaborator |
| POST | `/collection/{id}/join` | Accept an invitation. Body: `{"token": "..."}` |
| GET | `/collections/covers/{text}` | Search for cover icons |
| GET | `/collections/covers` | Featured cover icons |

To show the folder tree, combine `/user` (its `groups` list the root collections in order), `/collections` and `/collections/childrens`.

### Tags (`tags`)

`collectionId` is optional on every tag call. Leave it out to act on all collections.

| Method | Path | What it does |
|---|---|---|
| GET | `/tags/{collectionId}` | List tags with counts. `/tags` alone lists all |
| PUT | `/tags/{collectionId}` | Rename one tag: `{"tags": ["old"], "replace": "new"}`. Merge tags: list several in `tags` |
| DELETE | `/tags/{collectionId}` | Remove tags from every bookmark: `{"tags": ["a", "b"]}` |

### Highlights (`highlights`)

| Method | Path | What it does |
|---|---|---|
| GET | `/highlights` | All highlights. Query: `page`, `perpage` (50 max) |
| GET | `/highlights/{collectionId}` | Highlights in one collection |
| GET | `/raindrop/{id}` | A bookmark's highlights are in its `highlights` field |
| PUT | `/raindrop/{id}` | Add: `{"highlights": [{"text": "...", "note": "...", "color": "yellow"}]}`. Update: include the highlight's `_id` and the changed fields. Remove: `{"highlights": [{"_id": "...", "text": ""}]}` |

Colors: `blue`, `brown`, `cyan`, `gray`, `green`, `indigo`, `orange`, `pink`, `purple`, `red`, `teal`, `yellow` (the default).

### Filters (`filters`)

| Method | Path | What it does |
|---|---|---|
| GET | `/filters/{collectionId}` | Counts by tag, type, domain, broken links, duplicates, untagged and favorites. Query: `search`, `tagsSort` (`-count` or `_id`) |

Use this to find duplicates and broken links before a cleanup.

### User (`user/authenticated`)

| Method | Path | What it does |
|---|---|---|
| GET | `/user` | The user's account, including `groups` (the sidebar order of collections) |
| GET | `/user/{name}` | A public user profile |
| PUT | `/user` | Update account settings, such as `groups` or `config` |
| GET | `/user/connect/{provider}` | Connect a social account (browser flow, not useful from here) |
| GET | `/user/connect/{provider}/revoke` | Disconnect a social account |

### Import, export and backups (`import`, `export`, `backups`)

| Method | Path | What it does |
|---|---|---|
| GET | `/import/url/parse?url=...` | Fetch a page's title, description and cover without saving it |
| POST | `/import/url/exists` | Check whether links are already saved. Body: `{"urls": [...]}`. Returns the matching bookmark IDs in `ids`. When none of the links is saved, it returns `"result": false`; that is not an error |
| POST | `/import/file` | Parse a browser bookmarks HTML file without saving anything (`--form import=@PATH`). Returns the folders and bookmarks it found; save them with `POST /raindrops` |
| GET | `/raindrops/{collectionId}/export.{format}` | Export as `csv`, `html` or `zip`. Query: `sort`, `search`. Redirect the output to a file |
| GET | `/backups` | List backups |
| GET | `/backup/{id}.{format}` | Download a backup as `html` or `csv` |
| GET | `/backup` | Start a new backup. Raindrop emails the user when it is ready |

### Access tokens (`authentication/token`)

A test token from the Raindrop app settings never expires and is all a single user needs. Use OAuth only when the user asks for it, for example to give a token to an app that other people sign in to. OAuth access tokens expire after two weeks.

These commands need `RAINDROP_CLIENT_ID` and `RAINDROP_CLIENT_SECRET`, found the same way as the token. They save the new tokens to `~/.config/raindrop/credentials` and print only whether it worked.

| Command | What it does |
|---|---|
| `scripts/raindrop.sh oauth-url REDIRECT_URI` | Print the address where the user approves access. The redirect address must match the one set on the Raindrop app. After approval, Raindrop sends the browser to that address with `?code=...` |
| `scripts/raindrop.sh oauth-token CODE REDIRECT_URI` | Trade that code for an access token and a refresh token |
| `scripts/raindrop.sh oauth-refresh` | Get a new access token with the saved refresh token |

A token in the environment or in `./.env` wins over the saved one. If calls still fail with `Unauthorized` after a refresh, an older token in one of those places is the cause.
