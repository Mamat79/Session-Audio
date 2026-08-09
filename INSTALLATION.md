# Installation de Session Audio

## Installer

1. Telecharger `Session-Audio-Setup-1.0.0.exe` depuis la page Releases du depot prive.
2. Verifier le SHA-256 avec le fichier `.sha256.txt` fourni dans la meme release.
3. Lancer l'installeur et choisir si le raccourci Bureau doit etre cree.

Le logiciel est installe par defaut dans :

`%LOCALAPPDATA%\Programs\Session Audio`

Les raccourcis du menu Demarrer sont :

- `Session Audio` ;
- `Session Audio - Restaurer` ;
- `Session Audio - Configuration`.

Le lanceur demande les droits administrateur, ouvre l'interface puis se ferme. Le raccourci de restauration affiche une console uniquement pendant la restauration et la ferme a la fin.

## Premiere installation

La configuration initiale est volontairement prudente : aucune application, aucun service, aucun processus, aucune carte reseau et aucune option de securite sensible ne sont actives automatiquement.

Le fichier `Audio-Live.apps.json` est conserve lors des mises a jour. Une reinstallation ne remplace donc pas les profils et choix existants.

## Mettre a jour

Lancer le nouvel installeur par-dessus la version existante. Les scripts et le lanceur sont remplaces ; la configuration, les sauvegardes et les journaux sont conserves.

## Desinstaller

Utiliser les Parametres Windows ou le menu Demarrer. Si `Audio-Live.state.json` existe, la desinstallation est bloquee : lancer d'abord `Session Audio - Restaurer` afin de remettre le poste dans son etat precedent.

La configuration et les journaux ne sont pas effaces automatiquement. Ils restent disponibles pour une reinstallation ou une suppression manuelle volontaire.

## Avertissement SmartScreen

La version 1.0.0 n'est pas signee avec un certificat de signature de code. Windows peut afficher un avertissement SmartScreen. Le SHA-256 publie permet de verifier que le fichier telecharge correspond exactement au build publie.

## Construire localement

Prerequis : Windows PowerShell 5.1, .NET Framework 4 et Inno Setup 6.

Build generique :

```powershell
.\Build-Installer.ps1 -Test
```

Build personnel reprenant les applications et profils locaux, avec les options de securite forcees a l'arret :

```powershell
.\Build-Installer.ps1 -UseLocalConfiguration -Test
```

Les fichiers finaux sont places dans `dist`.
