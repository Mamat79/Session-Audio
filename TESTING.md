# TESTING

## Tests actuels

Commandes executees :

```powershell
[System.Management.Automation.Language.Parser]::ParseFile(...)
.\Audio-Live.ps1 -NoGui -Simulate
Get-Content .\Audio-Live.apps.json -Raw -Encoding UTF8 | ConvertFrom-Json
```

Resultat :

- syntaxe OK ;
- JSON OK ;
- simulation OK.

## Tests a creer

Tests PowerShell/Pester :

- lecture config ;
- profils vides ;
- noms de profils doublons ;
- accents reseau ;
- bouton carte audio ;
- dry-run sans modification, y compris options securite ;
- restauration avec service absent ;
- conservation du state si restauration partielle ;
- restauration pare-feu / Defender sur machine de test ;
- mode `-NoGui` bloque si options securite sensibles demandees ;
- chemins avec espaces et accents ;
- application introuvable ;
- interface reseau introuvable.
