# Contributing to the Codex Knowledge Base

This document outlines how Managed Solution engineers can propose changes, additions, or corrections to the PowerShell Codex Agent knowledge base.

## Why Contribution Matters

The codex agent is only as good as its knowledge base. When you encounter a pattern that works well, a gap in our documentation, or a standard that needs updating, contributing back ensures the entire team benefits.

## Process

All changes follow a branch-and-review workflow:

1. **Create a feature branch** from `main` using the naming convention `docs/<topic>-<brief-description>` (e.g., `docs/auth-add-managed-identity-examples`).
2. **Make your changes** in the relevant markdown files. If you're adding a new document, follow the numbering convention in `best-practices/` and update the repo structure section in `README.md`.
3. **Open a pull request** against `main` with a clear description of what changed and why.
4. **Peer review** is required — at least one other engineer must approve before merge.
5. **Merge** using squash-and-merge to keep history clean.

## Writing Standards for Documents

When writing or editing documents in this repo, follow these guidelines so the agent can effectively parse and reference the content:

- Use clear, descriptive H2 (`##`) headers to delineate major topics. The agent uses these as retrieval boundaries.
- Include code examples for every pattern you describe. Abstract guidance without examples is difficult for the agent to action.
- When a practice relates to a specific compliance control, reference it inline (e.g., "This supports CMMC AC.L2-3.1.1 — Authorized Access Control").
- Keep language direct and imperative. Write "Use `Connect-MgGraph` with certificate-based auth" rather than "It is recommended that one might consider using…"
- Avoid ambiguity. If something is required, say "REQUIRED." If it's preferred but optional, say "PREFERRED."

## Proposing New Documents

If you believe a new topic area needs its own document, open an issue first describing the scope and why existing documents don't cover it. This prevents overlap and keeps the repo focused.
