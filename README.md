# kkk

Windows cache & junk-file cleanup research + tooling.

## Contents

| Path | What it is |
|---|---|
| [`docs/windows-cache-cleaner-comparison.md`](docs/windows-cache-cleaner-comparison.md) | Comparison of 15 free and paid Windows cleaners — features, prices, trust ratings, what to avoid, and a recommended 15-minute setup. |
| [`scripts/Clean-Junk.ps1`](scripts/Clean-Junk.ps1) | Safe PowerShell cleaner. **Dry-run by default** — measures every category, deletes nothing unless you pass `-Run`. |

## Quick start

```powershell
# See what can be reclaimed (deletes nothing)
.\scripts\Clean-Junk.ps1

# Then clean the safe categories
.\scripts\Clean-Junk.ps1 -Run

# Deeper, optional extras
.\scripts\Clean-Junk.ps1 -Run -IncludeRecycleBin -IncludeAppCaches -IncludeWindowsUpdateCache
```

The script also supports `-IncludeDism` (shrinks `WinSxS`, 10–40 min, irreversible) and
`-IncludeHibernation` (removes `hiberfil.sys`, loses hibernate/Fast Startup).

## Short version of the findings

- **Best free all-in-one:** Microsoft PC Manager
- **Best open source:** BleachBit (preview before every clean — there is no undo)
- **Best for privacy traces:** PrivaZer
- **Set-and-forget:** built-in Storage Sense
- **Find where space actually went:** WizTree / TreeSize Free
- **Avoid:** registry cleaners (reclaim ~0 MB, can break Windows), "free scan → pay to fix" tools, and PC-speedup suites
