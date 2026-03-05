# Managed Solution — PowerShell Codex Agent Knowledge Base

This repository serves as the authoritative knowledge base for the Managed Solution PowerShell Codex Agent, a Copilot Studio–powered assistant that helps internal engineers write, review, and scaffold PowerShell code that meets our organizational standards.

## Purpose

The codex agent uses these documents as grounding knowledge to provide three core capabilities:

- **Reference** — Engineers ask "how do we do X?" and get answers aligned with our standards, not generic internet advice.
- **Code Generation** — The agent scaffolds scripts, functions, and modules using our approved patterns, naming conventions, and compliance guardrails.
- **Code Review** — Engineers paste code and the agent evaluates it against these best practices, flagging deviations and suggesting improvements.

## Repository Structure

```
ms-codex-agent/
├── README.md                          # You are here
├── CONTRIBUTING.md                    # How to propose changes to standards
├── agent-instructions/
│   └── system-prompt.md               # Copilot Studio agent instructions
├── best-practices/
│   ├── 01-powershell-coding-standards.md   # Core language standards
│   ├── 02-authentication-patterns.md       # Auth for M365, Graph, Azure
│   ├── 03-graph-api-patterns.md            # Microsoft.Graph SDK v2 patterns
│   ├── 04-m365-module-patterns.md          # EXO, SPO, Teams, Security modules
│   ├── 05-error-handling-logging.md        # Try/catch, logging, alerting
│   ├── 06-module-structure.md              # How to structure PS modules
│   └── 07-compliance-guardrails.md         # CMMC/NIST compliance in code
├── templates/
│   ├── script-template.ps1                 # Starter template for standalone scripts
│   └── function-template.ps1               # Starter template for advanced functions
└── references/
    └── approved-modules.md                 # Approved PowerShell modules and versions
```

## How the Agent Uses This Repo

The Copilot Studio agent is configured with this repository as a knowledge source. When an engineer asks a question, the agent retrieves relevant sections from these documents and uses them to ground its response. The agent also references Microsoft Learn via MCP integration for official Microsoft documentation.

The hierarchy of authority is: **this repo** (our standards) > **Microsoft Learn** (official docs) > **agent general knowledge** (fallback). If our standards conflict with generic guidance, our standards win.

## Compliance Baseline

All guidance in this repository is written with CMMC Level 2 and NIST 800-171 controls in mind. Compliance is not a separate concern — it is embedded into every coding standard, authentication pattern, and operational procedure documented here.

## Maintaining This Knowledge Base

See [CONTRIBUTING.md](CONTRIBUTING.md) for the process to propose changes. All modifications to best practices documents require peer review before merge.
