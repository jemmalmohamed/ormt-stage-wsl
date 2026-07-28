# Dossiers sources fournis

Ce dossier est réservé aux projets ORMT fournis manuellement pour une
installation transportable. Le mode `Git` clone dans le système de fichiers
Linux de WSL, jamais dans ce dossier Windows, afin de rester rapide.

Pour installer sans nouveau clonage, place ici les trois dossiers complets :

```text
sources/
├── ormt-infra-stage-local-vps/
├── ormt-api/
└── ormt-web-v1/
```

Les dossiers `.git` sont facultatifs. L'installateur vérifie la structure puis
synchronise les projets dans le système de fichiers Linux de WSL avant
compilation. Une empreinte évite de recopier les projets inchangés.

Après un clonage dans `~/ormt-app/`, tu peux copier manuellement les trois
projets WSL vers ce dossier, puis transférer le dossier `ormt-stage-wsl` complet
sur une autre machine. Le mode `Auto` réutilisera alors ces projets sans nouveau
clonage ni mise à jour Git.

Ce mode évite Git, mais Internet reste nécessaire pour Ubuntu, Maven, npm et les
images Docker.
