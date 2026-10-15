---
paths:
  - "scripts/**"
  - ".claude/hooks/**"
---

# Skripte – Regeln für diese Pfade

Gilt zusätzlich zu `CLAUDE.md`. Skripte und Hooks sind CODEOWNERS-pflichtig.

- Reines ASCII, Umlaute als ae/oe/ue: PowerShell 5.1 liest Dateien ohne BOM in der ANSI-Codepage und zerstört Umlaute.
- Lokale Werkzeuge in PowerShell 5.1; Bash nur für Schritte, die auf dem Runner laufen (von CI und Veröffentlichung geteilt). Bash-Skripte mit unterscheidbaren Exit-Codes, nach jeder Änderung `bash -n`.
- Erfolg nur am Exit-Code (`$LASTEXITCODE`) messen, nie an `stderr`.
- Melden statt reparieren: Ein Skript stellt fest und berichtet, es ändert nicht still den Zustand.
- Niemals Inhalte von Schlüsseln oder Zertifikaten ausgeben.
