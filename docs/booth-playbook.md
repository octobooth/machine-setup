# Booth playbook

What to do before, during, and after an event, and how the booth accounts and their demo repos are kept clean. You can read this without logging in to anything. Each section lists the access and tools it needs.

## Where things live

| What | Where | Who can see it |
| --- | --- | --- |
| Machine setup scripts and this playbook | [`octobooth-demos/machine-setup`](https://github.com/octobooth-demos/machine-setup) | Anyone (public) |
| Demo scripts, templates, and the Demo Launcher | [`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) | Members of the `octobooth-demos` org (internal) |
| Admin scripts (wiping accounts, installing the weekly cleanup) | [`octobooth-demos/admin-tasks`](https://github.com/octobooth-demos/admin-tasks) | `octobooth-demos` org members (private) |
| Booth accounts | `octobooth-1` … `octobooth-10`, one per booth machine | |
| Org demo repos (ChatOps and security demos) | the `octobooth-demos` org | |

## Before the event: set up the booth machines

Follow [Setup Instructions](../README.md#setup-instructions) on each machine. Log in as that machine's **booth account**, not your personal account (see [GitHub CLI login](../README.md#github-cli-login)). Setup installs the GitHub Copilot app, the GitHub CLI, the Demo Launcher, and the demo repos.

## During the event

Ask Copilot to **"open the demo launcher"** and create demos from it. The launcher, the demo list, and per-demo notes are documented in the `repo-setup-scripts` README (org members only). Each demo repo gets the `demo-generated` topic, which is how the cleanups below find it.

## How demo repos get cleaned up

| Repos | Cleanup | When | Needs |
| --- | --- | --- | --- |
| Demo repos in each booth account | [Weekly cleanup](#weekly-cleanup-in-each-booth-account), a workflow that runs **in that account** | Mondays 08:00 UTC: `demo-generated` repos more than 7 days old. Or run it sooner yourself. | Nothing, it's automatic. To run it sooner: a browser signed in as that account. |
| Demo repos in the `octobooth-demos` org | [Org nightly cleanup](#org-nightly-cleanup) | Nightly 08:00 UTC: `demo-generated` repos more than 72 hours old | Nothing, it's automatic. To run it sooner: org member with write access to `repo-setup-scripts`. |
| **Everything** in the booth accounts | [Full reset after an event](#after-the-event-full-reset-of-the-booth-accounts) | When you run it | A Mac or Linux machine, the GitHub CLI, and access to `admin-tasks` |

08:00 UTC is midnight Pacific (1 AM during daylight saving time).

## Weekly cleanup in each booth account

Each booth account has a private repo, `octobooth-N/demo-cleanup`, with a workflow named **Weekly demo cleanup**. It runs as that account, using that account's own token, and only touches that account's repos:

- It deletes repos the account owns that have the `demo-generated` topic and are more than 7 days old.
- It never deletes repos without that topic, or the `demo-cleanup` repo itself.
- Nothing runs from the org, and no admin is needed once it's set up.

### Run it sooner (just a browser)

1. Sign in to github.com as the booth account and go to `https://github.com/octobooth-N/demo-cleanup/actions`, using that account's number.
2. Click **Weekly demo cleanup** in the left sidebar.
3. Click **Run workflow** on the right.
4. Set **older_than_days**:
   - `7` (the default) deletes the same repos as the Monday run.
   - `0` deletes **every** demo repo in the account, however new.
   - Any other number means "older than that many days".
5. Optionally tick **dry_run** to only list what it would delete.
6. Click the green **Run workflow** button. The run appears after a few seconds; open it to see what was deleted.

### Check that it's working

Open the account's `demo-cleanup` **Actions** tab. Each Monday should have a green run. If a run fails, GitHub emails the booth account, and the run's log says what's wrong. The usual cause is a revoked or deleted token; fix it by [setting up that account again](#set-up-or-repair-the-weekly-cleanup).

### Set up or repair the weekly cleanup

Needed for a new booth account, or when an account's cleanup reports a token problem. You need a Mac (or Linux), the GitHub CLI logged in to your own GitHub account, access to `admin-tasks`, and a browser where you can sign in as the booth account(s).

```bash
gh repo clone octobooth-demos/admin-tasks && cd admin-tasks   # or: cd admin-tasks && git pull
bash scripts/setup-weekly-cleanup.sh --accounts 3             # one account
bash scripts/setup-weekly-cleanup.sh                          # all of octobooth-1..10
bash scripts/setup-weekly-cleanup.sh --from 6                 # resume at octobooth-6
```

For each account, the script:

1. Prints and copies a link that creates a **classic** token with `repo`, `delete_repo`, and `workflow` ticked. The token's note names the account.
2. You open the link in a browser or profile signed in as **that** account, then check the avatar in the top right. Press `o` to open the link in your default browser instead.
3. You set **Expiration** to **No expiration**, generate the token, and paste it into the script. Your typing is hidden.
4. The script checks the token (right account, classic, right scopes, doesn't expire), creates the `demo-cleanup` repo if needed, adds the workflow, and saves the token as the `CLEANUP_TOKEN` secret.
5. It runs a dry-run test in Actions and shows what it found.

Rerunning is safe; it replaces the token. The token belongs to the booth account, not to you, so it keeps working whoever set it up and whatever machines are logged in. It stops working only if someone deletes or regenerates it in that account's **Settings → Developer settings → Personal access tokens (classic)**, where its note is `demo-cleanup weekly cleanup (octobooth-N)`.

## After the event: full reset of the booth accounts

`admin-tasks/scripts/wipe-accounts.sh` deletes **every** repo in each booth account, demo or not, except `demo-cleanup`. It goes one account at a time: log in (or switch) → list that account's repos → you confirm → delete → next account. It doesn't touch the org's repos or the booth machines' local folders.

### On a fresh Mac

1. Install [Homebrew](https://brew.sh), then the GitHub CLI: `brew install gh`.
2. Log in as yourself (an `octobooth-demos` org member) so you can download the admin scripts:

   ```bash
   gh auth login -h github.com
   gh repo clone octobooth-demos/admin-tasks && cd admin-tasks
   ```

   If `admin-tasks` is already on the machine, run `cd admin-tasks && git pull` instead.

### Run it

```bash
bash scripts/wipe-accounts.sh --dry-run    # list what would be deleted, change nothing
bash scripts/wipe-accounts.sh              # walk through octobooth-1..10
bash scripts/wipe-accounts.sh --from 5     # resume at octobooth-5
```

- **Logins.** For each booth account the GitHub CLI isn't logged in to yet, the script walks you through a browser login. Sign in to github.com as that account (a private window is easiest), press Enter, and paste the one-time code it shows. Type `s` to skip an account. Logins are remembered, so later runs don't ask again.
- **Confirming.** For each account it lists the repos, numbered. Type:
  - `WIPE` (in capitals) to delete them.
  - `k` to keep some, by number or name.
  - `s` to skip the account.
  - `q` to stop.

  Anything else, including lowercase `wipe`, shows a warning and asks again.
- **Finishing up.** At the end it prints a summary and, if anything was skipped or failed, the exact command to finish it.
- **Booth machines.** After a wipe, the clones in each booth machine's `~/repos` folder point at deleted repos. Remove them, or reset the machine with [setup](../README.md#setup-instructions).

The `admin-tasks` README has every option.

## Org nightly cleanup

Demo repos created in the `octobooth-demos` org (ChatOps and the security demos) are deleted by the **Clean up demos** workflow in `repo-setup-scripts` once they're more than 72 hours old. To run it sooner, org members with write access can either:

- open an issue in `repo-setup-scripts` and comment `/cleanup 24 --confirm` (any number of hours), or `/cleanup --all --confirm` after an event; or
- run **Clean up demos** from that repo's **Actions** tab.

Comments without `--confirm` are dry runs.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| A booth account's weekly cleanup run failed | Open the failed run. If it mentions `CLEANUP_TOKEN`, [set up that account again](#set-up-or-repair-the-weekly-cleanup). |
| Demo repos in a booth account aren't being deleted | Check they're more than 7 days old and have the `demo-generated` topic (shown under **About** on the repo page). To delete them now, [run the cleanup](#run-it-sooner-just-a-browser) with `older_than_days` set to `0`. |
| The setup script says a token belongs to the wrong account | The browser was signed in as another account. Delete that stray token in the other account's token settings, switch the browser to the right account, and make a new one. |
| `gh repo clone octobooth-demos/admin-tasks` says "Could not resolve" | Log in to the GitHub CLI as your own org-member account: `gh auth login -h github.com`. |
| The wipe script asks for `delete_repo` | Approve it in the browser while signed in as that booth account. |
