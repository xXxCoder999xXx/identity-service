# IdentityService

Produktionsnaher Microservice nach Clean/Hexagonal-Architektur (.NET 10, C# 14).
Das Projekt entsteht als vertikaler Durchstich: Automatisierungsfundament
(CI/CD, geschützter Merge, Docker, Zero Trust) vor der ersten Fachlogik.

## Grundprinzipien

- Open/Closed-Prinzip: neue Anforderungen durch Erweiterung, nicht Modifikation.
- Jede Warnung ist ein Build-Fehler (`Directory.Build.props`).
- Sicherheit durchgängig: keine Secrets im Repository, Least Privilege überall.
- Jede wesentliche Entscheidung ist als ADR dokumentiert: [`docs/adr/`](docs/adr/).

## Konventionen

- Commit-Nachrichten folgen [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `chore:`, ...).
- Integration ausschließlich über kurzlebige Feature-Branches und Pull Requests
  (Branch Protection wird mit der CI-Pipeline aktiviert).
