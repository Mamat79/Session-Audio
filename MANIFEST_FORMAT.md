# FORMAT DE RAPPORT SESSION AUDIO

Version cible : `session-audio-station-report/1`

## JSON

```json
{
  "formatVersion": "session-audio-station-report/1",
  "createdAt": "2026-07-11T00:00:00",
  "computerName": "",
  "profile": "",
  "mode": "simulation",
  "actions": [],
  "readiness": {}
}
```

## Champs par action

| Champ | Description |
|---|---|
| `category` | alimentation, service, processus, reseau, securite, application |
| `target` | element concerne |
| `currentState` | etat detecte |
| `expectedState` | etat demande par le profil |
| `action` | action prevue ou executee |
| `requiresAdmin` | droits administrateur requis |
| `result` | succes, ignore, erreur |
| `restoreSupported` | restauration possible |
| `message` | details |

## CSV

Le CSV doit reprendre les memes champs d'action dans un ordre stable.
