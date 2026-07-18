Session Audio - Mamat

Fichier a lancer :
- Audio-Live-Launch.bat
- Session Audio.lnk

Fichiers necessaires :
- Audio-Live.ps1 : script principal.
- Audio-Live.apps.json : memorise les logiciels, services et le plan d'alimentation choisi.
- Audio-Live-Restore.bat : restauration directe de la session precedente.
- Session Audio - Restaurer.lnk : raccourci de restauration directe.

Fichiers utiles mais pas toujours indispensables :
- Mode_Audio.pow : necessaire seulement si le plan "Mode Audio" doit etre recree/importe dans Windows.
- Session_Audio.ico : icone de la fenetre, optionnelle.

Fichiers crees automatiquement :
- Audio-Live.state.json : cree pendant une session pour permettre la restauration, puis supprime apres restauration.
- Logs AudioLive_*.log : journaux dans le dossier Logs du projet.

Onglets disponibles :
- Logiciels : programmes a lancer.
- Services : services Windows a arreter ou demarrer.
- Processus : applications/processus a fermer pendant la session, puis relancer si possible a la restauration.
- Reseau : adaptateurs reseau a desactiver ou activer, puis restaurer.
- Diagnostic : lecture seule, etat reel du PC, drivers et BIOS si Windows les fournit.

Astuce :
- Survole une ligne pour voir sa description.
- Clique sur un en-tete de colonne pour trier la liste.
- Coche Simulation pour generer un rapport sans rien appliquer.
- Utilise Profil et Sauver profil pour memoriser plusieurs configurations.
- Utilise Renommer, Dupliquer et Supprimer pour gerer les profils.
- Dans Reseau, le bouton Carte audio marque une carte comme a conserver : elle ne sera pas desactivee.
- Le rapport de session est ecrit dans le fichier AudioLive_*.log.
- Avant chaque modification de Audio-Live.apps.json, une sauvegarde .bak-YYYYMMDD-HHMMSS est creee.

Note :
Le lanceur .bat est garde car c'est le moyen le plus fiable de double-cliquer et de demander les droits administrateur sur Windows.
