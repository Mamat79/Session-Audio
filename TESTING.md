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

## Test de l'installeur 1.0.0

`Build-Installer.ps1 -Test` verifie automatiquement :

- compilation du lanceur natif ;
- compilation Inno Setup ;
- installation silencieuse dans un dossier `%TEMP%` unique ;
- presence des fichiers indispensables ;
- syntaxe du script installe ;
- configuration de securite sensible desactivee ;
- simulation PowerShell 5.1 sans creation de snapshot ;
- desinstallation silencieuse ;
- suppression du dossier de test.

Le build generique et le build personnel ont passe ce test le 2026-08-09.

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
