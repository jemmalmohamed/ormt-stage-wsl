# Dossiers sources fournis

Pour installer ORMT sans cloner les dépôts Git, place ici les trois dossiers
complets :

```text
sources/
├── ormt-infra-stage-local-vps/
├── ormt-api/
└── ormt-web-v1/
```

Les dossiers `.git` sont facultatifs. L'installateur vérifie la structure puis
copie les projets dans le système de fichiers Linux de WSL avant compilation.

Ce mode évite Git, mais Internet reste nécessaire pour Ubuntu, Maven, npm et les
images Docker.

