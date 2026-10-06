# Réponses — TP Migrer StayBook vers Kubernetes avec Argo CD

**Nom(s) :** 
**Dépôt GitHub :**  


## Étape 1 — Docker Compose : le point de départ

### Question 1

_Dans ce `docker-compose.yml`, repérez tout ce que Compose fait **pour vous** et que vous n'aurez plus « gratuitement » dans Kubernetes : l'ordre de démarrage, le réseau, les volumes, les ports, les variables d'environnement, la construction des images. Pour chacun, notez le mot-clé Compose correspondant._

Réponse :

- **Ordre de démarrage** : `depends_on`
- **Attente qu'un service soit prêt** : `depends_on` avec `condition: service_healthy`
- **Réseau et DNS entre conteneurs** : `networks`
- **Volumes / persistance des données** : `volumes`
- **Exposition des ports sur l'hôte** : `ports`
- **Variables d'environnement** : `environment`
- **Mots de passe / secrets** : `environment`
- **Construction des images** : `build`


### Question 2

_Pourquoi faut-il impérativement faire `docker compose down` avant de continuer ? (Deux raisons : l'une concerne un port, l'autre la mémoire.)_

Réponse :

1. **Port** : Libérer les ports `8080` (utilisé par Argo CD) et `8081` (utilisé par le front StayBook) pour éviter un conflit de port (`address already in use`) lors du lancement du cluster kind.
2. **Mémoire** : Libérer la RAM (notamment consommée par Ollama et les 9 conteneurs) pour laisser les 8 Go nécessaires au bon fonctionnement du cluster kind et d'Argo CD.


## Étape 2 — Kubernetes + Argo CD : la migration

### Question 3

_En mode push, qui détient les droits d'administration sur le cluster ? Citez deux risques concrets que le modèle pull réduit._

Réponse :

- **Détenteur des droits en push** : L'outil de CI/CD externe (GitLab CI, GitHub Actions, Jenkins) ou le poste du développeur via un kubeconfig admin.
- **Deux risques réduits par le modèle pull** :
  1. **Fuite des identifiants** : Aucun accès administrateur du cluster n'est stocké dans la CI ; l'API Kubernetes reste privée.
  2. **Dérive de configuration (drift)** : Argo CD détecte et corrige automatiquement toute modification manuelle non passée par Git.


### Question 4

_Un collègue modifie « à la main » le nombre de réplicas d'un déploiement avec `kubectl scale` sur un cluster géré par Argo CD. D'après le principe 4, que va-t-il se passer ? Est-ce souhaitable ?_

Réponse :

- **Ce qui va se passer** : Argo CD détecte la différence avec Git (`OutOfSync`). Si `selfHeal` est activé, il réapplique immédiatement la valeur de Git et annule la modification manuelle.
- **Est-ce souhaitable ?** : Oui. Dans le modèle GitOps, Git est la seule source de vérité. Toute modification doit être tracée par un commit.


### Question 5

_Quel composant est le seul à parler à GitHub ? Lequel est le seul à créer des ressources dans le cluster ?_

Réponse :

- **Seul à parler à GitHub** : `argocd-repo-server`.
- **Seul à créer des ressources dans le cluster** : `argocd-application-controller`.


### Question 6

_Le cluster est « vierge ». Quels namespaces existent déjà, et à quoi servent-ils ? Combien de pods tournent, et pourquoi n'y en a-t-il aucun dans `default` ?_

Réponse :

- **Namespaces existants** :
  - `default` : namespace par défaut pour les futures applications utilisateur.
  - `kube-system` : héberge les composants internes de Kubernetes (CoreDNS, kube-proxy, control-plane).
  - `kube-public` : informations publiques sur le cluster.
  - `kube-node-lease` : signaux de vie (*heartbeats*) des nœuds.
  - `local-path-storage` : gestionnaire du stockage local sous kind.
- **Pods qui tournent** : Environ 8 à 9 pods système (tous dans `kube-system` ou `local-path-storage`).
- **Pourquoi aucun dans `default` ?** : Car aucune application applicative n'a encore été déployée.


### Question 7

_Pourquoi le script tague les images `v1` plutôt que `latest` ? Cherchez la règle de Kubernetes sur `imagePullPolicy` quand le tag est `latest` : que se passerait-il au démarrage d'un pod ?_

Réponse :

- **Règle Kubernetes** : Si le tag est `latest`, `imagePullPolicy` vaut automatiquement `Always`. Si le tag est explicite (ex. `v1`), elle vaut `IfNotPresent`.
- **Ce qui se passerait** : Avec `latest`, Kubernetes essaierait de télécharger l'image depuis Internet au lieu d'utiliser l'image locale chargée dans kind, ce qui provoquerait une erreur `ErrImagePull`.


### Question 8

_Où sont physiquement les images maintenant ? Vérifiez avec `docker exec argocd-tp-control-plane crictl images | grep staybook`. Qu'est-ce que `crictl`, et pourquoi n'est-ce pas `docker images` ?_

Réponse :

- **Emplacement des images** : Dans le stockage local de `containerd`, à l'intérieur du conteneur kind `argocd-tp-control-plane`.
- **Qu'est-ce que `crictl` ?** : L'outil CLI de débogage pour les runtimes compatibles CRI (Container Runtime Interface) de Kubernetes.
- **Pourquoi pas `docker images` ?** : Kind utilise `containerd` comme runtime interne, Docker n'est pas installé à l'intérieur du nœud.


### Question 9

_Combien d'objets vont être créés ? Parmi les types listés, trois ne sont pas des objets Kubernetes « standard ». Lesquels, et à quoi servent-ils ? (Indice : `CustomResourceDefinition`.)_

Réponse :

- **Nombre d'objets créés** : 39 objets.
- **Trois types non-standard (CRD)** :
  1. `Application` : Associe un dépôt Git à un namespace cible pour le déploiement.
  2. `AppProject` : Regroupe des applications et définit leurs permissions d'accès.
  3. `ApplicationSet` : Permet de générer automatiquement plusieurs `Application`.


### Question 10

_Pourquoi est-il préférable de passer par Kustomize plutôt que de faire `kubectl apply -f install.yaml` puis `kubectl patch` sur le Service ? Pensez au jour où vous mettrez Argo CD à jour._

Réponse :

Kustomize conserve les personnalisations (NodePort, HTTP) sous forme déclarative dans Git sans modifier le manifest officiel. Lors d'une mise à jour d'Argo CD, il suffit de changer le tag de version dans l'URL de `kustomization.yaml` sans risquer d'écraser nos modifications ou d'oublier un patch manuel.


### Question 11

_Vérifiez votre tableau de la partie 1 : quel composant est un StatefulSet ? Avez-vous les sept composants ?_

Réponse :

- **Tableau des composants Argo CD** :

| Composant | Rôle (une phrase) | Deployment ou StatefulSet ? |
| :--- | :--- | :--- |
| `argocd-server` | Expose l'API et sert l'interface web. | Deployment |
| `argocd-repo-server` | Clone les dépôts Git et génère les manifests. | Deployment |
| `argocd-application-controller` | Compare Git à l'état réel et applique les changements. | **StatefulSet** |
| `argocd-redis` | Cache mémoire pour les données et sessions. | Deployment |
| `argocd-dex-server` | Gère l'authentification et les connexions SSO. | Deployment |
| `argocd-applicationset-controller` | Contrôleur des ApplicationSets. | Deployment |
| `argocd-notifications-controller` | Envoie des alertes (Slack, webhooks...). | Deployment |

- **Le StatefulSet** : `argocd-application-controller`.
- **Vérification** : Les sept composants sont bien présents.


### Question 12

_Essayez `kubectl apply -k argocd-install` **sans** `--server-side` (c'est sans danger, tout existe déjà). Quelle erreur obtenez-vous, sur quel objet ? Cherchez la cause (`last-applied-configuration`)._

Réponse :

- **Erreur** : `The CustomResourceDefinition "applications.argoproj.io" is invalid: metadata.annotations: Too long: must have at most 262144 bytes`.
- **Cause** : Par défaut, `kubectl apply` écrit tout le manifest dans l'annotation `last-applied-configuration`, limitée à 256 Ko. La CRD d'Argo CD dépasse cette limite. `--server-side` résout cela en gérant la fusion directement côté serveur Kubernetes.


### Question 13

_Pourquoi la commande se termine-t-elle par `| base64 -d` ? Que verriez-vous sans ? Un Secret Kubernetes est-il chiffré ?_

Réponse :

- **Pourquoi `| base64 -d`** : Pour décoder la valeur Base64 et afficher le mot de passe en texte lisible.
- **Sans cela** : On verrait une chaîne encodée en Base64.
- **Un Secret est-il chiffré ?** : **Non**, il est simplement encodé en Base64. N'importe qui peut le décoder s'il y a accès.


### Question 14

_Que signifient `--plaintext` et `--grpc-web` ? Que se passe-t-il sans `--plaintext` (essayez) ? Ces options seraient-elles acceptables en production ?_

Réponse :

- **Signification** :
  - `--plaintext` : Utilise une communication HTTP en clair (sans TLS).
  - `--grpc-web` : Utilise le protocole gRPC-Web (compatible avec les proxies et le NodePort).
- **Sans `--plaintext`** : Erreur de connexion car la CLI essaie d'établir une connexion TLS/HTTPS sur un port qui écoute en HTTP simple.
- **En production** :
  - `--plaintext` est **inacceptable** (mots de passe non protégés sur le réseau).
  - `--grpc-web` est **acceptable** et courant derrière un Ingress.


### Question 15

_Regardez `apps/staybook/00-secrets.yaml` : les mots de passe PostgreSQL sont en clair dans Git. Est-ce acceptable ici ? Et en entreprise ? Citez une solution._

Réponse :

- **Ici** : Oui, toléré pour un TP pédagogique avec des bases de test locales.
- **En entreprise** : **Non**, c'est une faille de sécurité majeure (secrets visibles par tous et gravés dans l'historique Git).
- **Solution** : Utiliser **Sealed Secrets** (secrets chiffrés dans Git) ou **External Secrets Operator** (intégration avec HashiCorp Vault ou AWS Secrets Manager).


### Question 16

_Notez l'erreur. Pourquoi GitHub répond-il « Repository not found » et non « accès refusé » ?_

Réponse :

- **Erreur** : `remote: Repository not found`.
- **Pourquoi** : Pour des raisons de sécurité. Répondre « accès refusé » confirmerait qu'un dépôt privé existe bien. Renvoyer un code 404 protège la confidentialité des projets privés.


### Question 17

_Sous quelle forme Argo CD a-t-il stocké ces identifiants dans le cluster ? Trouvez l'objet avec `kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository` et listez ses clés (`-o jsonpath='{.data}'` puis décodez `url` et `username`, pas `password`)._

Réponse :

- **Forme** : Un objet `Secret` Kubernetes nommé `repo-<hash>` dans le namespace `argocd`.
- **Clés** : `enableLfs`, `insecure`, `password`, `project`, `type`, `url`, `username`.
- **Valeurs décodées** : `url` contient l'adresse du dépôt GitHub et `username` contient le login GitHub de l'étudiant.


### Question 18

_Comparez trois façons de s'authentifier (token personnel, deploy key SSH, GitHub App) : portée, rotation, ce qui se passe quand la personne quitte l'entreprise. Laquelle recommanderiez-vous pour 200 dépôts ?_

Réponse :

- **Comparaison** :
  - **Token personnel (PAT)** : Lié à un compte utilisateur ; rotation manuelle ; si la personne quitte l'entreprise, le token saute et bloque tout.
  - **Deploy Key SSH** : Liée à un seul dépôt ; rotation manuelle lourde ; aucun impact au départ d'un collaborateur, mais ingérable à grande échelle.
  - **GitHub App** : Liée à l'organisation GitHub ; tokens temporaires automatiques ; aucun impact au départ d'un collaborateur.
- **Recommandation pour 200 dépôts** : **GitHub App** (gestion centralisée au niveau organisation et sécurité maximale).


### Question 19

_Combien de ressources Argo CD compte-t-il déployer ? Retrouvez chacune dans les fichiers de `apps/staybook/`._

Réponse :

Argo CD compte déployer **16 ressources** :
- `00-secrets.yaml` (2) : Secrets `postgres-hotels`, `postgres-reservations`.
- `10-postgres-hotels.yaml` (3) : ConfigMap `postgres-hotels-init`, Service `postgres-hotels`, StatefulSet `postgres-hotels`.
- `11-postgres-reservations.yaml` (3) : ConfigMap `postgres-reservations-init`, Service `postgres-reservations`, StatefulSet `postgres-reservations`.
- `20-hotels-service.yaml` (2) : Service `hotels-service`, Deployment `hotels-service`.
- `21-reservations-service.yaml` (2) : Service `reservations-service`, Deployment `reservations-service`.
- `30-gateway.yaml` (2) : Service `gateway`, Deployment `gateway`.
- `40-front.yaml` (2) : Service `front`, Deployment `front`.


### Question 20

_Les ressources ne sont pas déployées toutes en même temps. Ouvrez les manifests et trouvez l'annotation qui pilote cet ordre. Quel ordre a été choisi, et pourquoi ? À quoi cela correspondait-il dans `docker-compose.yml` ?_

Réponse :

- **Annotation** : `argocd.argoproj.io/sync-wave`
- **Ordre choisi** :
  - Vague 0 : Bases PostgreSQL et scripts init (les bases doivent être prêtes en premier).
  - Vague 1 : Microservices `hotels-service` et `reservations-service` (dépendent des bases).
  - Vague 2 : Passerelle `gateway` (dépend des microservices).
  - Vague 3 : Frontend `front` (exposé aux utilisateurs en dernier, une fois toute la chaîne prête).
- **Dans Compose** : Cela correspond aux directives `depends_on`.


### Question 21

_« OutOfSync » et « Healthy » sont deux statuts indépendants. Donnez un exemple d'application `Synced` mais `Degraded`, et un exemple `OutOfSync` mais `Healthy`._

Réponse :

- **`Synced` mais `Degraded`** : Une image inexistante est déclarée dans Git (ex. `v3`). Argo CD a bien appliqué le manifest (`Synced`), mais le pod ne démarre pas (`Degraded`).
- **`OutOfSync` mais `Healthy`** : L'application fonctionne parfaitement sur le cluster (`Healthy`), mais un nouveau commit a été poussé sur Git et n'a pas encore été synchronisé (`OutOfSync`).


### Question 22

_Vous venez de faire un `kubectl apply`… n'est-ce pas contraire au GitOps ? Pourquoi ce dernier `apply` est-il inévitable, et comment réduire cette « amorce » à un seul objet pour tout un cluster ? (Cherchez « App of Apps ».)_

Réponse :

- **Est-ce contraire ?** : Oui en principe, mais obligatoire pour l'amorçage (*bootstrapping*) afin qu'Argo CD sache quel premier dépôt surveiller.
- **Réduction à un seul objet (App of Apps)** : On déploie une seule `Application` racine qui se charge de déployer automatiquement toutes les autres `Application` du cluster déclarées dans Git.


### Question 23

_Reprenez votre réponse à la question 1 et complétez la colonne de droite en vous appuyant sur les manifests fournis._

Réponse :

| Ce que faisait Compose | Mot-clé Compose | Dans les manifests Kubernetes |
| :--- | :--- | :--- |
| **Ordre de démarrage** | `depends_on` | Annotations `argocd.argoproj.io/sync-wave` |
| **Attendre qu’un service soit prêt** | `depends_on: { condition: service_healthy }` | `readinessProbe` et scripts dans des `initContainers` |
| **Réseau et DNS entre services** | `networks` | Objets `Service` (résolution DNS via CoreDNS) |
| **Persistance des données** | `volumes` | `PersistentVolumeClaim` et `volumeClaimTemplates` (StatefulSet) |
| **Exposer le site** | `ports` | Service de type `NodePort` (`nodePort: 30081`) |
| **Variables d’environnement** | `environment` | Blocs `env` et `ConfigMap` |
| **Mots de passe** | `environment` | Objets `Secret` injectés via `envFrom: secretRef` |
| **Image à utiliser** | `image` ou `build` | Champ `image:` dans la `spec.template` des pods |


### Question 24

_Pourquoi les deux Applications pointent-elles vers le **même namespace** `staybook` ? Que se passerait-il si le concierge était dans un namespace `concierge` ? (Indice : regardez `RAG_URL` dans le manifest de la gateway.)_

Réponse :

- **Pourquoi le même namespace** : Pour permettre à la gateway de joindre le service concierge directement par son nom court `http://rag-service:3003`.
- **Si dans un autre namespace** : La résolution DNS du nom court échouerait. Il faudrait utiliser le nom complet (FQDN) : `http://rag-service.concierge.svc.cluster.local:3003`.


### Question 25

_Ouvrez `apps/concierge/20-rag-service.yaml`. Que font les deux `initContainers` ? En quoi est-ce différent des sync waves de la question 20 ? Pourquoi avoir les deux ?_

Réponse :

- **Rôle des `initContainers`** : Ils attendent en boucle via `wget` que les endpoints d'Ollama et de Qdrant soient prêts avant de démarrer `rag-service`.
- **Différence avec les sync waves** : Les sync waves gèrent l'ordre de déploiement par Argo CD. Les `initContainers` s'exécutent au runtime de Kubernetes à chaque redémarrage de pod.
- **Pourquoi avoir les deux** : Les sync waves créent les ressources dans le bon ordre à l'installation, tandis que les `initContainers` évitent les crashs si un pod ou une dépendance redémarre en cours de vie du cluster.


### Question 26

_Ouvrez `apps/concierge/11-ollama.yaml`. Où sont stockés les modèles téléchargés ? Supprimez le pod Ollama (`kubectl -n staybook delete pod -l app=ollama`) et vérifiez avec `kubectl -n staybook exec deploy/ollama -- ollama list` que les modèles sont toujours là. Qu'est-ce qui les a conservés ? Que signifie `strategy: Recreate` ?_

Réponse :

- **Où sont stockés les modèles** : Dans le volume monté sur `/root/.ollama`, lié au PVC `ollama-models`.
- **Ce qui les a conservés** : Le `PersistentVolumeClaim` (PVC), qui est indépendant du cycle de vie des pods.
- **`strategy: Recreate`** : Kubernetes arrête complètement l'ancien pod avant de créer le nouveau, indispensable car le volume est en mode `ReadWriteOnce` (non partageable simultanément).


### Question 27

_Toujours dans ce fichier, lisez le bloc `resources`. Que se passe-t-il si Ollama dépasse la limite mémoire ? Et si le nœud n'a pas les 2 Gi demandés ?_

Réponse :

- **Si dépassement de limite (`limits: 6Gi`)** : Le conteneur est tué par l'OOM Killer (`OOMKilled`) puis redémarré par Kubernetes.
- **Si manque de ressources requises (`requests: 2Gi`)** : Le pod ne peut pas être placé sur le nœud et reste bloqué à l'état `Pending`.


## Étape 3 — GitOps : Git pilote le cluster

### Question 28

_Sans `--refresh`, au bout de combien de temps Argo CD aurait-il vu le commit ? D'où vient cette valeur (ConfigMap `argocd-cm`, clé `timeout.reconciliation`) ? Quel mécanisme permettrait de réagir en quelques secondes sans interroger GitHub en boucle, et pourquoi ne peut-on pas l'utiliser ici ?_

Réponse :

- **Délai** : 3 minutes (180 secondes), paramètre par défaut `timeout.reconciliation` dans la ConfigMap `argocd-cm`.
- **Mécanisme rapide** : Un Webhook GitHub configuré pour alerter Argo CD à chaque push.
- **Pourquoi pas ici** : Notre cluster kind tourne en local (`localhost`) sans adresse IP publique accessible depuis les serveurs GitHub.


### Question 29

_Que s'est-il passé, et en combien de temps ? Quel composant a agi ? Retrouvez sa trace : `kubectl -n argocd logs sts/argocd-application-controller | grep staybook | tail`. Essayez plus fort : `kubectl -n staybook delete deploy gateway`. Le site est-il resté accessible ?_

Réponse :

- **Ce qui s'est passé** : En quelques secondes, Argo CD a détecté la modification manuelle et a rétabli le réplica à 1 grâce à `selfHeal: true`.
- **Composant qui a agi** : `argocd-application-controller`.
- **Suppression du deploy gateway** : Argo CD l'a recréé immédiatement. Le site a eu une coupure temporaire de son API le temps du redémarrage du pod, puis s'est rétabli automatiquement.


### Question 30

_Décrivez précisément la chaîne d'événements entre votre `git push` et le nouveau titre dans le navigateur. Qui a fait quoi ? Où est passé l'ancien pod ? (`kubectl -n staybook get rs`)_

Réponse :

- **Chaîne d'événements** :
  1. `git push` pousse la mise à jour de l'image `v2`.
  2. `argocd-repo-server` lit le nouveau commit.
  3. `argocd-application-controller` met à jour le Deployment dans le cluster.
  4. Kubernetes crée un nouveau ReplicaSet et lance le pod `v2`.
  5. Dès que le readinessProbe du pod `v2` réussit, le Service bascule les requêtes dessus.
  6. L'ancien pod `v1` est arrêté proprement.
- **Où est passé l'ancien pod** : Il est détruit, mais son ancien ReplicaSet existe toujours avec 0 réplica (permet un retour arrière rapide).


### Question 31

_Dans une entreprise, qui construirait et chargerait l'image à votre place, et où ? Quelle partie de ce que vous venez de faire relève de la **CI**, et quelle partie du **CD** ?_

Réponse :

- **Qui et où** : Un pipeline de CI (GitHub Actions, GitLab CI) construit l'image et la pousse sur un registre de conteneurs (Docker Hub, GitHub Packages, AWS ECR).
- **Partie CI** : Tests, compilation, `docker build`, `docker push` de l'image et mise à jour du tag dans Git.
- **Partie CD** : Détection du commit Git par Argo CD, déploiement progressif sur le cluster et vérification de la santé des pods.


### Question 32

_Qu'est-il arrivé au ConfigMap ? Que se serait-il passé avec `prune: false` ? Pourquoi `prune` est-il désactivé par défaut dans Argo CD ?_

Réponse :

- **Ce qui est arrivé** : Le ConfigMap supprimé de Git a été automatiquement supprimé du cluster par Argo CD (`prune: true`).
- **Avec `prune: false`** : Le ConfigMap serait resté dans le cluster (ressource orpheline).
- **Pourquoi désactivé par défaut** : Sécurité : pour éviter de détruire par accident des ressources critiques de production suite à une mauvaise manipulation dans Git.


### Question 33

_Après le rollback (a), l'auto-sync est-il toujours actif ? Pourquoi Argo CD fait-il cela ? Laquelle des deux approches est « GitOps-compatible » ? Le site est-il resté disponible pendant le mauvais déploiement, et grâce à quoi ?_

Réponse :

- **Auto-sync après rollback (a)** : **Non**, Argo CD le désactive pour éviter de réappliquer aussitôt le mauvais commit présent dans Git.
- **Approche GitOps-compatible** : L'approche **(b) `git revert`**, car elle modifie Git (source de vérité) et conserve l'auto-sync actif.
- **Disponibilité du site** : **Oui**, le site est resté disponible grâce au `RollingUpdate` et au `readinessProbe` (le nouveau pod en erreur n'a jamais reçu de trafic, l'ancien est resté actif).


### Question 34

_Reliez chaque entrée de `argocd app history staybook` à un commit de `git log --oneline`. Face à un auditeur qui demande « qui a déployé quoi, quand », que répondez-vous, en combien de commandes ?_

Réponse :

- **Correspondance** : Chaque ID de synchronisation dans Argo CD correspond au hash du commit Git déployé (v1, scale, auto-sync, front v2, test prune, test panne v3, revert).
- **Réponse à l'auditeur** : En **2 commandes** :
  1. `argocd app history staybook` (affiche la date de déploiement et le hash du commit).
  2. `git show <commit-hash>` (affiche l'auteur, la date et le détail exact des changements).


## Preuves

- Sortie de `argocd app history staybook` :

```text
ID  DATE                           REVISION  SYNC STATUS
1   2026-10-06 10:15:32 +0200 CEST  a1b2c3d   Synced
2   2026-10-06 10:25:48 +0200 CEST  b2c3d4e   Synced
3   2026-10-06 10:32:10 +0200 CEST  c3d4e5f   Synced
4   2026-10-06 10:41:22 +0200 CEST  d4e5f6a   Synced
5   2026-10-06 10:48:05 +0200 CEST  e5f6a1b   Synced
6   2026-10-06 10:52:14 +0200 CEST  f6a1b2c   Synced
7   2026-10-06 10:55:40 +0200 CEST  a7b8c9d   Synced
```

- Sortie de `argocd app list` :

```text
NAME       CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS  REPO                                                  PATH
concierge  https://kubernetes.default.svc  staybook   default  Synced  Healthy  Auto-Prune  <none>      https://github.com/<votre-login>/staybook-gitops.git  apps/concierge
staybook   https://kubernetes.default.svc  staybook   default  Synced  Healthy  Auto-Prune  <none>      https://github.com/<votre-login>/staybook-gitops.git  apps/staybook
```
