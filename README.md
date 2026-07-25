# Installateur ORMT Stage pour Windows et WSL

Cet installateur prépare une infrastructure complète sous Ubuntu WSL, la
valide, puis installe et teste le Stage métier ORMT.

Le profil développeur est activé par défaut. Il comprend Traefik, Portainer,
Jenkins, Homepage, Grafana, Prometheus, cAdvisor et Node Exporter.

## Parcours recommandé

Double-clique sur :

```text
03-Installer-Tout.bat
```

L'installateur effectue automatiquement :

1. la préparation d'Ubuntu WSL et de `systemd` ;
2. l'installation de l'infrastructure complète ;
3. le redémarrage de WSL lorsque le groupe Docker doit être actualisé ;
4. la validation de l'infrastructure ;
5. la construction et le démarrage du Stage métier ;
6. les tests HTTP finaux.

Aucune relance manuelle n'est requise après l'ajout au groupe Docker.

## Menu guidé

`Installer-ORMT.bat` propose :

```text
1. Installation complète recommandée
2. Infrastructure uniquement
3. Stage métier uniquement
4. Vérifier l'installation
5. Réparer ou reprendre
6. Configuration
7. Réinitialisation / suppression
0. Quitter
```

Les raccourcis disponibles à la racine sont :

```text
01-Installer-Infrastructure.bat
02-Installer-Stage-Metier.bat
03-Installer-Tout.bat
04-Verifier-Installation.bat
```

`setup.bat` et `setup.cmd` sont conservés comme alias de compatibilité.

## Provenance des projets

### Détection automatique

Le mode utilisé par défaut recherche les trois projets dans `sources/`. Si les
trois dossiers sont valides, ils sont copiés vers WSL. Sinon, les dépôts Git
sont clonés ou mis à jour.

### Dossiers fournis

Place les projets ainsi :

```text
sources/
├── ormt-infra-stage-local-vps/
├── ormt-api/
└── ormt-web-v1/
```

Les dossiers `.git` ne sont pas obligatoires. Les projets Windows ne sont
jamais compilés directement depuis `/mnt/c` ou `/mnt/d` : une copie est créée
dans `~/ormt-app/` pour conserver les performances Linux.

Ce mode évite Git, mais nécessite toujours Internet pour Ubuntu, Maven, npm et
les images Docker.

### Git

Les URLs et branches se configurent dans `config/.env`. Le mode Git refuse
d'écraser les modifications locales et utilise uniquement des mises à jour
`fast-forward`.

## Configuration

Dans le menu, sélectionne `6. Configuration`. Le fichier `config/.env` est créé
depuis `config/.env.example`, puis ouvert dans le Bloc-notes.

Valeurs principales :

```text
ORMT_SOURCE_MODE=auto
ORMT_INSTALL_DEV_TOOLS=true
ORMT_SKIP_TESTS=false
ORMT_DOCKER_PULL_PARALLEL=4
```

Lors d'une première installation, les images de l'infrastructure sont
téléchargées avec une progression visible et jusqu'à quatre téléchargements
simultanés. Les relances réutilisent les images déjà présentes.

Les images PostgreSQL, Keycloak, MinIO et Nextcloud sont également préchargées
en parallèle. Les deux API sont compilées simultanément avec le cache Maven
persistant de WSL, puis seules leurs images d'exécution sont assemblées.

L'état persistant est conservé dans :

```text
~/.local/state/ormt-stage/
```

Une mise à jour de l'installateur ne supprime pas cet état ni les volumes
Docker.

## Commandes avancées

Depuis PowerShell :

```powershell
.\installer\windows\setup.ps1 -Mode Full -SourceMode Auto
.\installer\windows\setup.ps1 -Mode Infrastructure -SourceMode Provided
.\installer\windows\setup.ps1 -Mode Stage -SourceMode Git
.\installer\windows\setup.ps1 -Mode Diagnostic
.\installer\windows\setup.ps1 -Mode Repair -SourceMode Auto
.\installer\windows\setup.ps1 -Mode ResetStage -ConfirmDestructive
.\installer\windows\setup.ps1 -Mode RemoveWsl -ConfirmDestructive
.\installer\windows\setup.ps1 -Mode RestartWsl
```

Depuis Ubuntu WSL, après installation :

```bash
cd ~/ormt-app/ormt-stage-wsl
./installer/wsl/commands/status-stage.sh
./installer/wsl/commands/start-stage.sh
./installer/wsl/commands/stop-stage.sh
./installer/wsl/commands/reset-stage.sh
```

`reset-stage.sh` est destructif et demande de saisir `RESET`. Il n'est jamais
appelé automatiquement.

## Réinitialisation et nouveau départ

L'option `7. Réinitialisation / suppression` du menu propose deux niveaux :

- **Réinitialiser uniquement le Stage métier** supprime ses conteneurs, volumes
  et données (PostgreSQL, Keycloak, MinIO, Nextcloud, API et frontend). Ubuntu
  WSL, Docker, l'infrastructure partagée, les sources et les caches sont
  conservés. Relance ensuite `02-Installer-Stage-Metier.bat`.
- **Supprimer complètement Ubuntu-24.04** exécute la désinscription WSL de cette
  distribution. Tous ses fichiers, conteneurs, volumes, images, sources et
  caches sont définitivement supprimés. Les fichiers Windows du présent
  dossier restent intacts. Relance ensuite `03-Installer-Tout.bat`.

Chacune de ces deux actions destructives demande une phrase de confirmation
explicite et n'est jamais déclenchée automatiquement après un échec
d'installation.

Le même sous-menu permet aussi de **redémarrer uniquement `Ubuntu-24.04`**.
L'installateur exécute un arrêt ciblé de cette distribution, attend son
redémarrage et vérifie qu'elle répond avant de continuer. Les données et les
autres distributions WSL ne sont pas touchées. Pour cibler une autre
distribution depuis PowerShell, utilise par exemple :

```powershell
.\installer\windows\setup.ps1 -Mode RestartWsl -Distro "Ubuntu-24.04"
```

## URLs principales

- Frontend : http://ormt-web.localhost
- API : http://ormt-core-api.localhost/api/v1
- Swagger : http://ormt-core-api.localhost/v3/api-docs
- Keycloak : http://localhost:8092
- MinIO : http://localhost:9000
- Traefik : http://traefik.localhost
- Portainer : http://portainer.localhost
- Jenkins : http://jenkins.localhost
- Homepage : http://lab.localhost
- Grafana : http://grafana.localhost
- Prometheus : http://prometheus.localhost

## Journaux et reprise

Les journaux sont écrits dans `logs/`. Chaque phase affiche sa durée.

En cas d'interruption, relance le même BAT. Les contrôles réels déterminent les
phases à reprendre. Les volumes et données Stage sont conservés.

Le message final suivant signifie que tous les contrôles demandés sont passés :

```text
SUCCÈS — mode Full terminé et validé
```
