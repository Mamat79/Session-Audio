# WINDOWS ACTIONS

Actions actuellement supportees :

| Categorie | Action | Restauration |
|---|---|---|
| Alimentation | Activer le plan choisi | Oui |
| Alimentation | Reglages CPU/USB du plan | Via plan precedent |
| Services | Demarrer/arreter service liste blanche | Oui, etat precedent |
| Processus | Fermer processus choisi | Relance si chemin connu |
| Reseau | Activer/desactiver adaptateur liste blanche | Oui, etat precedent |
| Securite | Couper pare-feu Windows si coche | Oui, profils precedents |
| Securite | Couper scan temps reel Defender si coche | Oui, etat precedent |
| Securite | Suspendre taches planifiees Defender si coche | Oui, etat precedent |

Actions volontairement non faites :

- desactivation definitive Windows Update ;
- modification UAC ;
- modification chiffrement ;
- modification protections de connexion ;
- arret force du service Defender protege par Windows ;
- clics automatiques dans des applications.
