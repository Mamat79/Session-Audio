# CLEANUP REPORT - Session Audio

## Mise a jour du 2026-08-09

- Le projet est maintenant un depot Git prive sur `main`.
- `Audio-Live.apps.json` reste une configuration locale ignoree par Git.
- `Audio-Live.apps.example.json` remplace la configuration machine dans les sources publiees.
- Les anciens raccourcis `.lnk` figes ont ete remplaces par des raccourcis generes par l'installeur.
- Les sorties `installer/build`, `installer/output` et `dist` sont regenerables et ignorees.
- `Audio-Live.state.json` et les sauvegardes locales restent conserves hors Git.

Date : 2026-07-11

## Perimetre

Dossier audite : `D:\Cloud\OneDrive - Radio France\AudioPro\Session Audio`

Independance respectee : aucune connexion ou dependance creee vers PATATE, DanteConfigEditorV3, Planning-To-ICS ou TLC.

## Etat Git

Le dossier n'est pas un depot Git :

- pas de branche `main` verifiable ;
- pas de `git status` disponible ;
- pas de tag annote possible ;
- pas de commit possible ;
- pas de push possible.

Aucun depot Git n'a ete initialise automatiquement.

Sauvegarde locale de securite creee avant travaux :

`D:\Cloud\OneDrive - Radio France\AudioPro\Session Audio.safety-20260711-112537`

## Inventaire

| Type | Constat |
|---|---|
| Langage | Windows PowerShell 5.1 compatible |
| Interface | Windows Forms |
| Configuration | `Audio-Live.apps.json` |
| Etat restauration | `Audio-Live.state.json` |
| Plan alimentation | `Mode_Audio.pow` |
| Lanceurs | `Audio-Live-Launch.bat`, `Audio-Live-Restore.bat`, raccourcis `.lnk` |
| Medias reels | Aucun fichier audio/video/session DAW detecte dans ce dossier ; hors perimetre volontaire |
| Secrets | Aucun motif evident detecte |
| Logs | Generes hors dossier via `..\Logs` |
| Sauvegardes | Plusieurs `Audio-Live.apps.json.bak-*` et `Audio-Live.ps1.bak-*` presentes |

## Formats audio/session/DAW

Non applicable. Le script ne doit pas lire de sessions DAW, parser WAV/BWF/iXML, copier des medias ou preparer une livraison audio. Il prepare/restaure l'environnement Windows pour une session audio.

## Elements nettoyables

Aucun fichier n'a ete supprime pendant cette passe.

Nettoyage possible, mais non applique automatiquement :

| Element | Decision |
|---|---|
| Logs de developpement | Ignorer via `.gitignore`; suppression manuelle seulement apres validation |
| `Audio-Live.state.json` | Ne pas supprimer : signale une session precedente non restauree |
| Sauvegardes `.bak-*` | Ne pas supprimer : retour arriere utile |
| Raccourcis `.lnk` | Conserver |
| `Mode_Audio.pow` | Conserver |
| `Session_Audio.ico` | Conserver |

## Code mort / doublons / documentation obsolete

Rien n'a ete supprime. Le script principal reste monolithique et doit etre separe progressivement avant tout nettoyage de code.

Points a revoir plus tard :

- fonctions GUI et logique Windows dans un seul fichier ;
- anciennes sauvegardes nombreuses, mais utiles pour retour arriere ;
- documentation `README.txt` a completer par `README.md`.

## Action realisee

- Ajout de `.gitignore`.
- Creation de ce rapport.
- Ajout de l'onglet `Securite` le 2026-07-12.
- Ajout documentation projet poste audio, restauration et actions Windows.
- Aucune suppression.
- Aucun media modifie.
- Aucune session reelle modifiee.
