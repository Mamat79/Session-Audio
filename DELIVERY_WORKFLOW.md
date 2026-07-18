# WORKFLOW SESSION AUDIO

## Objectif

Preparer le poste Windows pour une session audio, puis revenir au mode bureau normal.

## Avant application

- lire le profil ;
- analyser l'etat actuel ;
- afficher la simulation ;
- avertir si reseau, pare-feu ou Defender sont modifies ;
- sauvegarder l'etat precedent.

## Pendant application

- appliquer dans l'ordre ;
- journaliser chaque action ;
- permettre annulation ;
- ne pas modifier ce qui n'est pas dans la liste blanche.

## Apres session

- utiliser `Restaurer` ;
- remettre plan, services, reseau, pare-feu et Defender comme avant ;
- conserver le journal.
