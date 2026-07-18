# PREFLIGHT POSTE AUDIO

Session Audio ne controle pas les fichiers audio. Le preflight concerne uniquement l'etat du poste Windows avant travail audio.

## Controle cible

Chaque controle poste doit produire un statut :

- Information ;
- Avertissement ;
- Erreur ;
- Erreur bloquante.

## Points a detecter

- droits administrateur ;
- plan d'alimentation ;
- veille et extinction ecran ;
- economie USB ;
- applications audio installees et lancees ;
- services necessaires ;
- interfaces reseau ;
- carte audio reseau a conserver ;
- peripheriques audio ;
- scan Defender si option demande ;
- pare-feu si option demande ;
- processus de fond ;
- espace disque disponible ;
- etat de restauration precedent.

## Principe de securite

Le preflight est toujours en lecture seule. Il ne modifie jamais le poste.
