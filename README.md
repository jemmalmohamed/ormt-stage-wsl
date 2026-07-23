# ORMT Stage WSL

Point d'entrée simple pour installer et démarrer ORMT Stage dans Ubuntu WSL.

## 1. Si Ubuntu WSL n'est pas encore installé

Depuis PowerShell en administrateur :

```powershell
wsl --install -d Ubuntu-24.04
```

Redémarre Windows si demandé, puis ouvre **Ubuntu 24.04** depuis le menu Démarrer.

Au premier lancement, crée l'utilisateur Linux quand Ubuntu le demande. Utilise un nom simple, sans espace ni accent, par exemple :

```text
ormt
```

Vérifie ensuite :

```bash
whoami
sudo whoami
```

Le deuxième résultat doit être :

```text
root
```

## 2. Lancer l'installation automatique

Depuis PowerShell Windows, utilise :

```powershell
.\setup.bat
```

Sur une machine neuve, ouvre d’abord **Ubuntu 24.04** depuis le menu Démarrer
et termine la création de l’utilisateur Linux. Ferme ensuite Ubuntu et lance
`setup.bat`.

La fenêtre affiche les logs en direct et garde une copie dans le dossier `logs`.

À l’étape `ACTION REQUISE`, tape simplement le mot de passe de l’utilisateur
Ubuntu, puis appuie sur `Entrée`. Le curseur ne bouge pas et aucun caractère
ne s’affiche pendant la saisie : le mot de passe est quand même pris en compte.

Si la fenêtre affiche `Sélection ORMT Stage WSL Setup` dans la barre de titre, l'installation est en pause parce que tu as cliqué dans la fenêtre noire. Appuie sur `Échap` pour reprendre.

Le lanceur conserve maintenant le terminal directement connecté à WSL. La
saisie du mot de passe fonctionne normalement et les lignes de log restent
alignées.

Alternatives Windows :

```powershell
.\setup.cmd
.\setup.ps1
```

Depuis Ubuntu WSL, utilise :

```bash
./setup.sh
```

N'utilise pas `./setup.sh` directement dans PowerShell. C'est un script Linux.

Le script s'occupe de :

- copier le dossier vers `~/ormt-app/ormt-stage-wsl` si besoin ;
- créer `.env` ;
- configurer l'utilisateur Linux courant ;
- activer `systemd` si nécessaire ;
- installer les outils requis ;
- cloner les 3 dépôts applicatifs s'ils sont absents ;
- installer Docker, Traefik, Jenkins et le réseau `proxy` ;
- démarrer les services Stage ;
- afficher le diagnostic final.

Si `systemd` vient d'être activé, le script s'arrête. Lance alors depuis PowerShell :

```powershell
wsl --shutdown
```

Puis rouvre Ubuntu et relance :

```bash
cd ~/ormt-app/ormt-stage-wsl
./setup.sh
```

Pendant les étapes longues, comme l'installation Ansible ou Docker, le script affiche régulièrement :

```text
Installation et configuration ORMT Stage toujours en cours
```

Ne fais pas `Ctrl+C` pour rafraîchir le log. Cela arrête l'installation.

## 3. URLs après démarrage

- Frontend : http://ormt-web.localhost
- API : http://ormt-core-api.localhost/api/v1
- Swagger API : http://ormt-core-api.localhost/v3/api-docs
- Keycloak : http://localhost:8092
- MinIO : http://localhost:9000
- Jenkins : http://jenkins.localhost
- Traefik : http://traefik.localhost

Si le navigateur Windows n'ouvre pas les domaines `.localhost`, ajoute ces lignes dans `C:\Windows\System32\drivers\etc\hosts` :

```text
127.0.0.1 traefik.localhost
127.0.0.1 lab.localhost
127.0.0.1 jenkins.localhost
127.0.0.1 portainer.localhost
127.0.0.1 grafana.localhost
127.0.0.1 prometheus.localhost
127.0.0.1 ormt-web.localhost
127.0.0.1 ormt-core-api.localhost
127.0.0.1 ormt-kc.localhost
127.0.0.1 ormt-nextcloud.localhost
127.0.0.1 ormt-minio-console.localhost
127.0.0.1 ormt-minio-api.localhost
```

## 4. Commandes utiles

```bash
./setup.sh          # installation complète automatique depuis Ubuntu WSL
./start-stage.sh    # démarrer ou redémarrer Stage
./status-stage.sh   # vérifier l'état
./stop-stage.sh     # arrêter sans supprimer les données
./reset-stage.sh    # supprimer les conteneurs et volumes Stage
```

Les logs Windows sont écrits ici :

```text
ormt-stage-wsl\logs\
```

En cas d’échec, la fin du log affiche la commande, la ligne et le code erreur.
Il est possible de relancer `setup.bat` : les composants déjà installés sont
détectés et réutilisés.

Depuis PowerShell Windows, la commande principale est :

```powershell
.\setup.bat
```

`reset-stage.sh` est destructif pour les données ORMT Stage. Il ne supprime pas Traefik.

## 5. Dépannage rapide

Si le lanceur indique qu’Ubuntu n’est pas encore initialisé :

1. ouvre **Ubuntu 24.04** depuis le menu Démarrer ;
2. attends la fin de l’initialisation ;
3. crée le nom d’utilisateur et le mot de passe Linux demandés ;
4. ferme Ubuntu, puis relance `setup.bat`.

Si tu vois :

```text
bash: ./setup.sh: No such file or directory
```

Tu n'es pas dans le bon dossier. Retrouve le script :

```bash
find /mnt/c/Users/admin -maxdepth 5 -type f -name setup.sh
```

Puis va dans le dossier trouvé :

```bash
cd /mnt/c/Users/admin/chemin/vers/ormt-stage-wsl
./setup.sh
```

Si Docker affiche `permission denied`, lance :

```bash
newgrp docker
docker ps
```

Si Docker ne démarre pas, relance :

```bash
sudo service docker start
./status-stage.sh
```

Si tu vois des logs VS Code comme :

```text
[main ...] StorageMainService
[main ...] update#setState
```

Tu as lancé `setup.sh` depuis PowerShell ou Windows a ouvert le fichier avec VS Code. Relance avec :

```powershell
.\setup.bat
```
