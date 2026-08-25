# Installateur ORMT Stage pour Windows et WSL

Cet installateur prépare une infrastructure complète sous Ubuntu WSL, la valide,
puis installe et teste le Stage métier ORMT. Les dossiers présents dans
`sources/` peuvent être réutilisés sur une autre machine sans nouveau clonage
Git.

Le profil développeur est activé par défaut. Il comprend Traefik, Portainer,
Jenkins, Homepage, Grafana, Prometheus, cAdvisor et Node Exporter.

## Parcours recommandé

Double-clique sur :

```text
03-Installer-Tout.bat
```

L'installateur effectue automatiquement :

1. l'enregistrement des domaines `*.ormt.localhost` dans le fichier `hosts` Windows ;
2. la préparation d'Ubuntu WSL et de `systemd` ;
3. la sélection d'`Ubuntu-24.04` comme distribution WSL par défaut ;
4. l'installation de l'infrastructure complète ;
5. le redémarrage de WSL lorsque le groupe Docker doit être actualisé ;
6. la validation de l'infrastructure ;
7. la construction et le démarrage du Stage métier ;
8. les tests HTTP finaux ;
9. la proposition facultative d'un test de redémarrage à froid de WSL.

Windows affiche une demande d'autorisation administrateur pour mettre à jour
le fichier `C:\Windows\System32\drivers\etc\hosts`. Accepte-la afin que les
adresses Stage soient accessibles depuis le navigateur. L'installateur gère un
bloc ORMT isolé et le retire lors de la suppression complète de la distribution.

Les images d'exécution des API sont construites à partir de contextes temporaires
contenant uniquement les JAR compilés. L'image du renderer PDF est construite
depuis `ormt-api/ormt-pdf-renderer` avec l'image officielle Playwright. La
construction du Stage ne dépend donc pas des règles `.dockerignore` des dépôts
applicatifs, qui peuvent rester adaptées au processus de production.

Le Stage active également l'injection des utilisateurs Keycloak de test via une
surcharge Compose locale à l'installateur. Le profil et le déploiement de
production restent inchangés.

Les branches applicatives utilisées par défaut pour l'API et le frontend sont
`main`. Elles restent exécutées avec les fichiers et variables du profil Stage.

Aucune relance manuelle n'est requise après l'ajout au groupe Docker.

Sur une distribution neuve, l'absence de Docker est reconnue comme un état
normal de première installation : l'installateur ne présente plus une longue
liste de contrôles en échec avant de commencer.

Lors des modes `Full` et `Infrastructure`, l'installateur exécute également :

```powershell
wsl --set-default Ubuntu-24.04
```

Cette commande garantit que les commandes WSL lancées sans option `-d`
utilisent bien `Ubuntu-24.04`, même lorsqu'une autre distribution est déjà
installée sur la machine. Elle ne supprime ni ne modifie les autres
distributions WSL.

## Menu guidé

`Installer-ORMT.bat` propose :

```text
1. Installation complète recommandée
2. Infrastructure uniquement
3. Stage métier uniquement
4. Vérifier l'installation
5. Réparer ou reprendre
6. Configuration
7. Maintenance globale locale
8. Réinitialisation / suppression
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

Le mode utilisé par défaut recherche dans `sources/` uniquement les projets
nécessaires à l'opération demandée. Si les dossiers requis sont valides, ils
sont synchronisés vers WSL sans accès à Git. Sinon, les dépôts nécessaires sont
clonés directement dans le système de fichiers Linux de WSL pour éviter les
lenteurs importantes de `/mnt/c` et `/mnt/d`.

Le périmètre dépend du mode d'installation :

- `Infrastructure` synchronise uniquement `ormt-infra-stage-local-vps` ;
- `Stage` synchronise uniquement `ormt-api` et `ormt-web-v1` ;
- `Full` et `Repair` synchronisent les trois projets.

### Dossiers fournis

Place les projets ainsi :

```text
sources/
├── ormt-infra-stage-local-vps/
├── ormt-api/
└── ormt-web-v1/
```

Les dossiers `.git` ne sont pas obligatoires en mode `Provided`. Seuls les
projets nécessaires au mode demandé doivent être présents. Les projets
Windows ne sont jamais compilés directement depuis `/mnt/c` ou `/mnt/d` : une
copie optimisée est créée dans `~/ormt-app/provided/` pour conserver les
performances Linux. Une empreinte par projet évite toute nouvelle copie lorsque
les fichiers n'ont pas changé.

Ce mode évite Git, mais nécessite toujours Internet pour Ubuntu, Maven, npm et
les images Docker.

### Git rapide dans WSL

Les URLs et branches se configurent dans `config/.env`. Le mode Git clone ou met
à jour uniquement les dépôts requis dans `~/ormt-app/` et utilise des mises à
jour `fast-forward`. Si un dépôt contient des modifications locales,
l'installateur affiche leur liste et demande de taper exactement
`REINSTALLER`. Cette confirmation supprime les modifications suivies et les
fichiers non suivis avant de reprendre la mise à jour. Une autre réponse annule
l'opération sans modifier le dépôt. Les fichiers ignorés par Git, les volumes
Docker et les données métier sont conservés. Aucun clonage ou copie automatique
n'est effectué dans le dossier Windows monté sous `/mnt/`.

Le mode `Stage` synchronise uniquement l'API et le frontend. Lorsque le socle
Docker et Traefik est déjà actif et validé, les commandes de démarrage, d'arrêt
et de réinitialisation du Stage ne nécessitent pas la présence du dépôt
`ormt-infra-stage-local-vps` dans `~/ormt-app/`.

Après avoir choisi une provenance `Git` ou `Auto` dans le menu, l'installateur
propose d'afficher les branches distantes. Si cette option est activée, chaque
dépôt requis ayant plusieurs branches présente une liste numérotée. La branche
configurée dans `config/.env`, ou à défaut la branche principale distante, est
présélectionnée. Un dépôt avec une seule branche est sélectionné automatiquement.

Les modes `Infrastructure` et `Full` réappliquent systématiquement le playbook
d'infrastructure après la synchronisation des sources, même lorsque les
services existants sont déjà opérationnels. Cette opération idempotente déploie
les nouvelles routes, fichiers Compose et configurations sans supprimer les
volumes ni les données existantes. Le mode `Repair` conserve son contrôle rapide
et ne réapplique l'infrastructure que si sa validation échoue.

Si un clonage a été interrompu avant la création de son index Git,
l'installateur conserve le dossier dans un sous-dossier `.incomplete/` de
`~/ormt-app/` puis recrée automatiquement un clone propre au lancement suivant.

Pour préparer ensuite un installateur transportable, l'utilisateur peut copier
manuellement les trois projets depuis WSL vers `ormt-stage-wsl/sources/`, puis
archiver le dossier complet. Sur une autre machine, le mode `Auto` détectera ces
dossiers et installera sans `git clone` ni `git fetch`. Internet peut cependant
rester nécessaire pour Ubuntu, Maven, npm et les images Docker.

## Configuration

Dans le menu, sélectionne `6. Configuration`. Le fichier `config/.env` est créé
depuis `config/.env.example`, puis ouvert dans le Bloc-notes.

Valeurs principales :

```text
ORMT_SOURCE_MODE=auto
ORMT_SELECT_GIT_BRANCHES=false
ORMT_INSTALL_DEV_TOOLS=true
ORMT_SKIP_TESTS=false
ORMT_DOCKER_PULL_PARALLEL=4
```

Lors d'une première installation, les images de l'infrastructure sont
téléchargées avec une progression visible et jusqu'à quatre téléchargements
simultanés. Les relances réutilisent les images déjà présentes.

Pendant les opérations longues, la sortie native des commandes APT, Ansible,
Docker, Maven et npm est affichée directement dans le terminal. Aucun bloc
d'avancement périodique n'est ajouté au flux.

L'actualisation APT utilise les mécanismes Ubuntu standards : trois tentatives
réseau et aucun téléchargement de traduction de descriptions de paquets. Si
APT échoue, les éventuels fichiers de dépôts tiers sont signalés pour le
diagnostic, mais l'installateur ne les supprime et ne les modifie jamais.
Un catalogue actualisé depuis moins de 15 minutes est réutilisé afin d'éviter
un second `apt-get update` pendant le même parcours.

Pour les dépôts GitHub privés, le nom utilisateur et le jeton sont demandés par
Git. Le jeton est placé uniquement dans le cache mémoire Git pendant 15 minutes,
afin d'éviter plusieurs saisies durant les clones ; il n'est pas écrit dans la
configuration du dépôt ou de l'installateur.

Les images PostgreSQL, Keycloak, MinIO et Nextcloud sont également préchargées
en parallèle. Les deux API sont compilées simultanément avec le cache Maven
persistant de WSL. Leurs images d'exécution et celle du renderer PDF sont
ensuite assemblées en parallèle. Le contrôle final exige que le renderer PDF
soit déclaré `healthy` avant de valider le Stage. Comme en production, aucun
port hôte n'est publié pour ce service : le Core API conteneurisé appelle le
renderer par son nom de service interne `http://ormt-pdf-renderer:3010`. Le
profil Docker de développement conserve séparément `localhost:3010` pour le
backend exécuté directement sur la machine de développement.

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
.\installer\windows\setup.ps1 -Mode Stage -SourceMode Git -SelectGitBranches
.\installer\windows\setup.ps1 -Mode Diagnostic
.\installer\windows\setup.ps1 -Mode Repair -SourceMode Auto
.\installer\windows\setup.ps1 -Mode Full -FinalWslRestart Always
.\installer\windows\setup.ps1 -Mode Diagnostic -FinalWslRestart Never
.\installer\windows\setup.ps1 -Mode MaintenanceOn
.\installer\windows\setup.ps1 -Mode MaintenanceOff
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
./installer/wsl/commands/set-global-maintenance.sh --active true
./installer/wsl/commands/set-global-maintenance.sh --active false
```

`reset-stage.sh` est destructif et demande de saisir `RESET` lorsqu'il est lancé
directement. Le mode `Stage` l'appelle seulement après validation du socle
minimal et confirmation explicite avec `REINSTALLER`. Cette réinitialisation
utilise uniquement les sources API et frontend ; elle conserve l'infrastructure
partagée même si son dépôt source n'est plus présent dans WSL.

## Maintenance globale locale

L'option `7. Maintenance globale locale` active ou désactive la page de secours
sur `http://ormt.localhost`. Elle utilise automatiquement le dépôt infrastructure
sélectionné lors de la dernière installation, exécute le playbook Ansible et
vérifie le résultat. Elle ne reconstruit pas le Stage et ne supprime aucun
conteneur métier, volume ou donnée.

L'action exige que l'infrastructure ait déjà été installée et que Docker soit
accessible dans `Ubuntu-24.04`.

## Réinitialisation et nouveau départ

### Installation, mise à jour et realm Keycloak

Le BAT demande explicitement l'action à effectuer :

- **DEPLOYER** : met à jour le code et redémarre avec `ORMT_ACTION=DEPLOYER`,
  sans importer ni supprimer les données ;
- **INITIALISER** : utilise temporairement
  `ORMT_ACTION=DEPLOYER_INITIALISER_DATA` pour créer notamment le realm `ormt`
  et importer `init-data`, sans vider préalablement les bases ;
- **RÉINITIALISER** : demande la confirmation `REINSTALLER`, supprime les
  volumes du Stage métier, puis effectue une initialisation complète.

Après une initialisation réussie, les API sont recréées avec
`ORMT_ACTION=DEPLOYER`. La valeur permanente du Stage reste donc
`DEPLOYER`. Une suppression complète des données n'est possible que par le
menu de réinitialisation et sa confirmation explicite.

L'option `8. Réinitialisation / suppression` du menu propose deux niveaux :

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
L'installateur exécute un arrêt ciblé de cette distribution, attend Docker,
détecte si le Stage est installé puis valide automatiquement l'infrastructure
ou l'ensemble des services métier. Les données et les autres distributions WSL
ne sont pas touchées. Pour cibler une autre distribution depuis PowerShell,
utilise par exemple :

```powershell
.\installer\windows\setup.ps1 -Mode RestartWsl -Distro "Ubuntu-24.04"
```

## URLs principales

- Frontend : http://ormt.localhost
- API : http://ormt-core-api.localhost/api/v1
- API de contenu : http://ormt-content-api.localhost/api/v1
- Swagger : http://ormt-core-api.localhost/v3/api-docs
- Keycloak : http://users.ormt.localhost
- MinIO : http://minio.ormt.localhost
- Console MinIO : http://minio-console.ormt.localhost
- Nextcloud : http://nextcloud.ormt.localhost
- Traefik : http://proxy.ormt.localhost
- Portainer : http://containers.ormt.localhost
- Jenkins : http://jenkins.ormt.localhost
- Homepage : http://homepage.ormt.localhost
- Grafana : http://grafana.ormt.localhost
- Prometheus : http://prometheus.ormt.localhost

## Identifiants de test

Les mots de passe du Stage local suivent le modèle `nomService@ormt` :

- PostgreSQL : utilisateur `ormt`, mot de passe `postgres@ormt`
- Keycloak : utilisateur `admin`, mot de passe `keycloak@ormt`
- MinIO : utilisateur `minio`, mot de passe `minio@ormt`
- Nextcloud : utilisateur `admin`, mot de passe `nextcloud@ormt`
- Portainer : utilisateur `admin`, mot de passe `portainer@ormt`
- Jenkins : utilisateur `admin`, mot de passe `jenkins@ormt`
- Grafana : utilisateur `admin`, mot de passe `grafana@ormt`

Ces valeurs sont réservées aux tests locaux. Après une installation déjà
initialisée, les volumes Docker conservent les anciens mots de passe. Le mode
`Stage` recrée les volumes métier ; pour Jenkins, Portainer et Grafana, il faut
également recréer leurs volumes, ce qui supprime leurs données locales.

## Journaux et reprise

Les journaux sont écrits dans `logs/`. Chaque phase affiche sa durée.

En cas d'interruption, relance le même BAT. Les contrôles réels déterminent les
phases à reprendre. Le mode `Repair` conserve les volumes ; le mode `Stage`
reste une réinstallation destructive nécessitant la confirmation
`REINSTALLER`.

Après les modes `Full`, `Infrastructure`, `Stage`, `Repair` et `Diagnostic`, la
question `Redémarrer WSL et vérifier le démarrage à froid ? [o/N]` est proposée.
La réponse par défaut est `Non`. Pour les scripts automatisés, utilise
`-FinalWslRestart Always` ou `-FinalWslRestart Never`; une entrée non interactive
avec la valeur `Ask` ne redémarre jamais WSL.

Le message final suivant signifie que tous les contrôles demandés sont passés :

```text
SUCCÈS — mode Full terminé et validé
```
