# Multi-Repo Setup — Keeping Devkit and Agent Repos in Sync

## Problem

Two repositories need to coexist:

| Repository | Purpose | Contains |
|-----------|---------|----------|
| `open_claw_on_gcp` | Private — agent-specific deployment | Specific agents, real configs, private SOUL.md files |
| `openclaw-gcp-devkit` | Public — reusable devkit | Shared infrastructure, scripts, sample agent, docs |

The **devkit** (infrastructure, scripts, Terraform, Makefile, tests) is the shared foundation.
The **agent repo** adds private agent definitions on top of it.

Without a sync strategy, the two repos will drift apart as either one evolves.

## Proposed Solution: Upstream/Downstream with Git Subtree or Manual Sync

### Option A: Git Remote + Cherry-Pick (Recommended — Simplest)

Use `openclaw-gcp-devkit` as the **upstream** source of truth for infrastructure.
Use `open_claw_on_gcp` as the **downstream** private repo that adds agents on top.

#### Setup (one-time)

```bash
# In your private repo (open_claw_on_gcp):
cd open_claw_on_gcp
git remote add devkit https://github.com/Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git
git fetch devkit
```

#### Workflow: Devkit → Private Repo (pull infrastructure updates)

When the devkit gets updated (Terraform changes, script improvements, Makefile updates):

```bash
cd open_claw_on_gcp
git fetch devkit
git log devkit/main --oneline    # Review what changed

# Cherry-pick specific infrastructure commits:
git cherry-pick <commit-hash>

# Or merge the full devkit main branch:
git merge devkit/main --no-commit
# Resolve any conflicts (agents/ will have differences)
git commit -m "Sync infrastructure from devkit"
```

#### Workflow: Private Repo → Devkit (push infrastructure improvements)

When you improve infrastructure in the private repo (fix a script, update Terraform):

```bash
cd openclaw-gcp-devkit
git remote add private https://github.com/Herz-Cloud-AI-GmbH/open_claw_on_gcp.git
git fetch private

# Cherry-pick only infrastructure commits (NOT agent-specific ones):
git cherry-pick <commit-hash>
git push origin main
```

#### What to sync vs. what to keep private

| Path | Sync direction | Notes |
|------|---------------|-------|
| `terraform/` | Devkit → Private | Infrastructure is shared |
| `scripts/` | Devkit → Private | Deployment scripts are shared |
| `config/` | Devkit → Private | Templates are shared |
| `Makefile` | Devkit → Private | Build targets are shared |
| `tests/` | Bidirectional | Tests should work for both repos |
| `docs/` | Devkit → Private | Docs use generic examples |
| `.devcontainer/` | Devkit → Private | Dev environment is shared |
| `agents/johndoe/` | Devkit only | Sample agent stays in devkit |
| `agents/<private>/` | Private only | Real agents never go to devkit |
| `AGENTS.md` | Devkit → Private | May need local edits |
| `.gitignore` | Devkit → Private | Shared ignore rules |

### Option B: GitHub Template Repository

Make `openclaw-gcp-devkit` a [GitHub template repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository).

**Pros:**
- New deployments can be created with "Use this template" button
- Clean starting point each time

**Cons:**
- No ongoing sync — template creates a one-time copy
- Infrastructure improvements must be manually ported
- Not suitable for keeping two active repos in sync

**Verdict:** Good for new users starting fresh, but doesn't solve the sync problem.

### Option C: Git Subtree (Advanced)

Use `git subtree` to embed the devkit as a subtree in the private repo.

```bash
# Add devkit as a subtree (one-time):
git subtree add --prefix=devkit https://github.com/Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git main --squash

# Pull updates from devkit:
git subtree pull --prefix=devkit https://github.com/Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git main --squash

# Push infrastructure changes back to devkit:
git subtree push --prefix=devkit https://github.com/Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git main
```

**Pros:**
- Bidirectional sync is built-in
- No submodule complexity

**Cons:**
- Requires restructuring the private repo to nest devkit under a `devkit/` prefix
- Makefile and paths would need to be adjusted
- Complexity doesn't justify the benefit for a two-repo setup

**Verdict:** Over-engineered for this use case.

## Recommendation

**Use Option A (Git Remote + Cherry-Pick)** for its simplicity:

1. The devkit is the canonical source for infrastructure (Terraform, scripts, Makefile, docs).
2. The private repo adds agent-specific directories and configs on top.
3. Infrastructure improvements flow bidirectionally via cherry-pick or merge.
4. Agent-specific code never leaves the private repo.
5. No restructuring needed — both repos share the same top-level layout.

The key discipline is: **make infrastructure changes in the devkit first**, then sync to the private repo. Agent-specific changes are made only in the private repo.

## Manual Push Instructions

Since automated cross-repo pushes aren't available, here's how to push the current devkit-ready branch to the new repo:

```bash
# From your local machine (with access to both repos):
git clone https://github.com/Herz-Cloud-AI-GmbH/open_claw_on_gcp.git
cd open_claw_on_gcp
git checkout copilot/setup-devkit-with-sample-agent

# Push to the devkit repo:
git remote add devkit https://github.com/Herz-Cloud-AI-GmbH/openclaw-gcp-devkit.git
git push devkit copilot/setup-devkit-with-sample-agent:main
```

---

**Status:** Proposal — awaiting approval before implementation.
