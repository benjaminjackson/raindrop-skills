# raindrop-skills

A Claude Code plugin that lets Claude read and manage your [Raindrop.io](https://raindrop.io) bookmarks. You ask in plain words ("what did I save about housing policy?", "tag these five links `to-read`"), and Claude calls the Raindrop API for you.

Your access token stays out of the conversation. Claude runs a small script that finds the token and sends it to Raindrop. Claude never sees the token.

## What you can ask for

- **Find things.** Search by word, tag, site or date. List the newest bookmarks. Count the bookmarks under each tag.
- **Save things.** Save one link or a batch of up to 100. Upload a PDF or an image as a bookmark.
- **Organize.** Add tags, rename or merge tags, move bookmarks between collections, and create, nest, merge or delete collections.
- **Clean up.** Find duplicates, broken links and bookmarks with no tags. Delete empty collections. Empty the Trash.
- **Highlights.** List, add, edit and remove highlights and their notes.
- **Share.** Invite people to a collection, change their access, or remove them.
- **Move data.** Export to CSV, HTML or ZIP. Read a browser's bookmarks file. Start a backup and download one.

The skill covers every endpoint in the [Raindrop API documentation](https://developer.raindrop.io). Claude asks you before each call that changes or deletes anything, and tells you how many bookmarks the call touches.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `curl` and [`jq`](https://jqlang.github.io/jq/) on your PATH
- A Raindrop.io account

## Install

In Claude Code:

```
/plugin marketplace add benjaminjackson/raindrop-skills
/plugin install raindrop@raindrop-skills
```

## Set up the token

1. Open [app.raindrop.io/settings/integrations](https://app.raindrop.io/settings/integrations).
2. Create a new app. Any name works.
3. Open the app's settings, create a **test token**, and copy it.
4. Save the token where the script can find it. Run this in your terminal and paste the token when asked. The token does not appear on screen or in your shell history:

   ```bash
   mkdir -p ~/.config/raindrop
   read -rs "token?Paste token: "   # zsh; in bash use: read -rsp "Paste token: " token
   echo "RAINDROP_API_TOKEN=$token" > ~/.config/raindrop/credentials
   chmod 600 ~/.config/raindrop/credentials
   unset token
   ```

A test token reads and writes only your own account, and it does not expire.

The script looks for `RAINDROP_API_TOKEN` in three places, in this order:

1. The environment
2. A `.env` file in the directory where Claude Code runs
3. `~/.config/raindrop/credentials`

Use the `.env` file when different projects need different Raindrop accounts. Keep that file out of version control.

## Use it

Ask Claude about your bookmarks:

```
What did I save last month about city budgets?
Save https://example.com/article and tag it to-read.
Which of my tags have only one bookmark?
Move everything tagged recipes into a new collection called Cooking.
Export my bookmarks to bookmarks.csv.
```

You can also run the script yourself. The path is everything after `https://api.raindrop.io/rest/v1`:

```bash
scripts=skills/raindrop/scripts

# The 10 newest bookmarks
$scripts/raindrop.sh GET '/raindrops/0?perpage=10' | jq -r '.items[] | "\(.title)\t\(.link)"'

# Save a link
$scripts/raindrop.sh POST /raindrop '{"link":"https://example.com","pleaseParse":{}}'

# Upload a PDF as a bookmark
$scripts/raindrop.sh PUT /raindrop/file --form file=@report.pdf
```

## OAuth

You need OAuth only when a test token is not enough, for example when an app must act for other people's accounts. OAuth access tokens expire after two weeks.

Add `RAINDROP_CLIENT_ID` and `RAINDROP_CLIENT_SECRET` (from the same app page) to the credentials file. Then:

```bash
# 1. Print the approval address. Open it in a browser and approve.
raindrop.sh oauth-url https://your-redirect-address

# 2. Raindrop sends the browser to your redirect address with ?code=... Trade the code for tokens.
raindrop.sh oauth-token THE_CODE https://your-redirect-address

# 3. Two weeks later, renew.
raindrop.sh oauth-refresh
```

The script saves the tokens to `~/.config/raindrop/credentials` and does not print them.

## Limits

- Raindrop allows 120 requests a minute for each user.
- A list call returns 50 bookmarks at most. Claude pages through longer lists.
- The bulk update and bulk delete endpoints do not accept "all bookmarks" as a target. They need one collection at a time.
- Permanent copies of pages need a Raindrop Pro account.
- The OAuth commands are not tested against a live app. The other features are tested with a test token.

## What's in the repo

```
.claude-plugin/plugin.json        plugin manifest
.claude-plugin/marketplace.json   marketplace listing
skills/raindrop/SKILL.md          instructions and endpoint reference for Claude
skills/raindrop/scripts/raindrop.sh   the script that calls the API
```

## License

MIT
