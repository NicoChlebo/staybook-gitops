# TP 2 — Réponses aux questions & Preuves
**Étudiant :** Nico Chlebik  
**Formation :** EFFICOM TECH 5 — Module Kubernetes & GitOps  
**Dépôt GitOps :** [https://github.com/NicoChlebo/staybook-gitops](https://github.com/NicoChlebo/staybook-gitops)  
**Dépôt Sources :** [https://github.com/NicoChlebo/staybook-src](https://github.com/NicoChlebo/staybook-src)  

---

## Partie 0 — Le cluster et l'état initial

### Question 1. Comparaison de kind-config.yaml avec le TP 1
- **Ce qui a été ajouté** : 
  - Redirection du port NodePort 30081 vers l'hôte (`8081` pour `staybook-dev`).
  - Redirection du port NodePort 30082 vers l'hôte (`8082` pour `staybook-prod`).
  - Argo CD écoute sur le NodePort 30080 (mappé sur `8085` sur l'hôte en raison d'un conflit local avec Oracle XE sur le port 8080).
- **Pourquoi la prod a besoin d'un port dédié** : Pour permettre de tester et d'accéder indépendamment à l'environnement de production et à l'environnement de développement sans collision de ports.

### Question 2. Persistance de la configuration du TP 1
- Tout ce qui avait été créé via la CLI au TP 1 (Applications, dépôts, secrets) résidait uniquement dans l'etcd du cluster sous forme de ressources Kubernetes (CRDs `Application`, etc.). 
- Lorsque le cluster a été détruit (`kind delete`), toute cette configuration en mémoire a disparu car elle n'était pas déclarée dans un dépôt Git.

---

## Partie 1 — Deux environnements propres avec Kustomize

### Question 3. Absence de namespace dans la base
- **Pourquoi c'est voulu** : La base (`base/staybook/`) regroupe les manifests communs réutilisables. Y coder en dur un namespace interdirait de l'instancier dans plusieurs environnements.
- **Qui le fixe et quand** : C'est l'overlay (`overlays/dev/kustomization.yaml` ou `overlays/prod/kustomization.yaml`) qui définit `namespace: staybook-dev` ou `staybook-prod`. Kustomize injecte dynamiquement ce namespace dans toutes les ressources au moment de la génération des manifests.

### Question 4. Comparaison de 20-hotels-service.yaml avec le TP 1
- Dans le TP 1, la variable `RAG_URL` pointait sur un service local au namespace `staybook`.
- Dans le TP 2, `RAG_URL` pointe sur `http://rag-service.concierge.svc.cluster.local:3003`. Le concierge est mutualisé dans son propre namespace `concierge`, accessible via son nom DNS complet (FQDN).

### Question 5. Différences entre dev et prod révélées par diff
1. **Namespace** : `staybook-dev` en dev vs `staybook-prod` en prod.
2. **Nombre de réplicas** : 1 réplica en dev vs 2 réplicas en prod pour les services sans état (`front`, `gateway`, `hotels-service`, `reservations-service`).
3. **Port NodePort du Front** : `30081` (port hôte 8081) en dev vs `30082` (port hôte 8082) en prod (via le patch `front-nodeport.yaml`).

### Question 6. Bloc images dans Kustomize
- `name: staybook-front` désigne le nom de l'image tel que déclaré dans le Deployment `base/staybook/10-front.yaml`.
- Si l'on ajoute `newName: ghcr.io/<login>/staybook-front` et un tag, Kustomize remplace la directive `image:` du conteneur dans le manifest généré du Deployment `front`.

### Question 7. Pourquoi pas 2 réplicas pour PostgreSQL
1. **Raison liée aux volumes (PVC)** : Les disques persistants locaux ont un mode d'accès `ReadWriteOnce` (RWO), interdisant à deux pods distincts de monter le même volume en écriture simultanément.
2. **Raison liée à PostgreSQL** : PostgreSQL ne supporte pas nativement l'écriture multi-maître sans configuration avancée de réplication (Streaming Replication primaire/secondaire) et gestion de failover (Patroni, etc.). Deux instances indépendantes sur le même volume corrompraient les données.

### Question 8. Conservation de l'historique du TP 1
- Conserver l'historique Git permet la traçabilité complète de l'évolution de l'infrastructure, l'auditabilité et la possibilité de comparer ou de revenir en arrière sur d'anciennes versions des manifests.

### Question 9. Détection de Kustomize par Argo CD
- Argo CD détecte automatiquement le moteur de templating en inspectant le contenu du dossier source : la présence d'un fichier `kustomization.yaml` (ou `kustomization.yml`) active automatiquement le plugin Kustomize.
- Vérification : `kubectl -n argocd get app staybook-dev -o jsonpath='{.status.sourceType}'` renvoie `Kustomize`.

### Question 10. Test du concierge avant son déploiement
- Une requête envoyée au concierge (`/api/chat`) échoue car le service `rag-service.concierge.svc.cluster.local` n'existe pas encore dans le cluster : la résolution DNS interne échoue (`ENOTFOUND`).

### Question 11. Cycle de vie des Applications créées en CLI
- Elles vivent dans l'etcd du cluster (`argocd/staybook-dev` et `argocd/staybook-prod`).
- Si le cluster est détruit ou si un administrateur les supprime accidentellement, elles sont perdues car elles n'étaient pas versionnées dans Git.

---

## Partie 2 — L'App of Apps et l'isolation des équipes

### Question 12. Analyse des AppProjects dans 00-projects.yaml
- **`platform`** :
  - Dépôt autorisé : `staybook-gitops.git`
  - Destinations : cluster local, namespaces `kube-system` et `*`
  - Ressources de cluster autorisées : toutes (`*/*`, y compris ClusterRole, CRDs)
- **`staybook-dev`** :
  - Dépôt autorisé : `staybook-gitops.git`
  - Destination : namespace `staybook-dev` uniquement
  - Ressources de cluster autorisées : aucune
- **`staybook-prod`** :
  - Dépôt autorisé : `staybook-gitops.git`
  - Destination : namespace `staybook-prod` uniquement
  - Ressources de cluster autorisées : aucune

### Question 13. Sync-wave "-1" sur les AppProjects
- Les sync-waves ordonnent l'application des ressources. La vague `-1` garantit que les `AppProject` sont créés et validés par le contrôleur Argo CD avant que les `Application` (vague 0 par défaut) ne tentent de s'y lier. Dans le cas contraire, la création des Applications échouerait avec une erreur de projet inexistant.

### Question 14. Finalizer resources-finalizer
- `resources-finalizer.argocd.argoproj.io` active la suppression en cascade : si une ressource `Application` est supprimée dans Argo CD, Kubernetes supprime automatiquement l'ensemble des ressources sous-jacentes créées par cette application (Deployments, Services, ConfigMaps, etc.).

### Question 15. Adoption des applications existantes par root
- Argo CD adopte les Applications existantes sans les récréer : il effectue un merge/patch de leur spécification en leur associant les nouveaux paramètres déclarés dans Git (notamment le rattachement à leur `AppProject`).

### Question 16. Avertissement sur le finalizer
- `kubectl` signale un avertissement car le finalizer appartient à un contrôleur tiers (Argo CD). Si l'opérateur Argo CD n'est pas opérationnel, les ressources portant ce finalizer ne pourront pas être libérées facilement.

### Question 17. Commande unique pour reconstruire le cluster
- Une seule commande suffit : `kubectl apply -f argocd/root.yaml`.
- L'Application racine découvre et déploie automatiquement l'ensemble des projets, de l'infrastructure (`platform`), du socle commun (`concierge`) et des applications applicatives (`staybook-dev`, `staybook-prod`).

### Question 18. Décomposition du FQDN
`rag-service.concierge.svc.cluster.local` :
- `rag-service` : Nom du Service Kubernetes
- `concierge` : Namespace hébergeant le Service
- `svc` : Type de ressource (Service) dans la zone DNS Kubernetes
- `cluster.local` : Domaine interne racine du cluster Kubernetes

### Question 19. Source des données du Concierge (HOTELS_URL)
- `HOTELS_URL` pointe sur `http://hotels-service.staybook-prod.svc.cluster.local:3001`.
- Le concierge utilise le catalogue d'hôtels de la **production** comme jeu de données de référence partagé pour générer ses embeddings et répondre aux requêtes.

### Question 20. Tentative d'évasion (Rogue Dev vers Prod)
- **Statut / Message** : L'Application passe en erreur de synchronisation :  
  `InvalidSpecError: application destination staybook-prod is not permitted in project 'staybook-dev'`.
- Les pods de production n'ont pas été modifiés : le contrôleur Argo CD applique strictement les frontières RBAC définies au niveau de l'AppProject.

### Question 21. Gouvernance de 00-projects.yaml
- Seule l'équipe **Plateforme / Sécurité / SRE** doit avoir les droits d'écriture sur `00-projects.yaml`.
- Cette règle s'applique sur GitHub via :
  1. Le fichier `.github/CODEOWNERS` restreignant l'approbation du dossier `argocd/` aux administrateurs de la plateforme.
  2. Les règles de protection de branche (Branch Protection Rules) imposant une revue obligatoire et interdisant les pushes directs sur `main`.

---

## Partie 3 — Chiffrer les secrets dans Git avec Sealed Secrets

### Question 22. Configuration de l'Application sealed-secrets
- L'Application pointe directement sur un **chart Helm** distant : `chart: sealed-secrets` avec `repoURL: https://bitnami-labs.github.io/sealed-secrets`.
- Elle ne contient pas de `path` Git car les manifests proviennent du chart Helm officiel, déployé dans `kube-system`.

### Question 23. La clé sealed-secrets-key
- **Créateur** : Le contrôleur Sealed Secrets lors de son premier démarrage.
- **Type** : `kubernetes.io/tls`.
- **Contenu** : La paire de clés asymétriques (clé privée `tls.key` pour déchiffrer, certificat public `tls.crt` pour chiffrer).
- **Si le cluster disparaît** : Sans sauvegarde préalable de ce secret (`tls.key`), tous les fichiers `SealedSecret` chiffrés dans Git deviennent définitivement indéchiffrables.

### Question 24. Mécanisme de récupération du certificat par kubeseal
- `kubeseal --fetch-cert` utilise la configuration locale (`~/.kube/config`), contacte l'API Kubernetes via le proxy d'API ou le service du contrôleur dans `kube-system`, et télécharge le certificat public exposé par le contrôleur.

### Question 25. Contenu de encryptedData
- Il s'agit des valeurs secrètes chiffrées de manière asymétrique (RSA-OAEP 4096 bits + AES-GCM 256 bits).
- Un tiers qui clone le dépôt ne peut pas retrouver les mots de passe car seule la clé privée présente dans le cluster peut réaliser le déchiffrement.

### Question 26. Pruning et recréation des Secrets Kubernetes
- En retirant `00-secrets.yaml` de Kustomize, Argo CD a automatiquement supprimé (pruné) l'ancien Secret en clair.
- Dès que le `SealedSecret` a été appliqué, le contrôleur Sealed Secrets a déchiffré la payload et recréé un Secret natif Kubernetes portant un `ownerReference` vers la ressource `SealedSecret`.

### Question 27. Prise en compte d'un nouveau mot de passe PostgreSQL
- PostgreSQL n'exécute ses scripts d'initialisation (`/docker-entrypoint-initdb.d/`) qu'à l'initialisation initiale du volume.
- Si le mot de passe est modifié dans le Secret sans réinitialiser la base ou sans exécuter manuellement `ALTER USER ... WITH PASSWORD`, PostgreSQL continuera d'utiliser l'ancien mot de passe stocké dans son volume de données.

### Question 28. Portabilité d'un SealedSecret entre namespaces
- Message d'erreur : `decryption error`.
- Explication : Le chiffrement par défaut (`strict`) intègre le nom du Secret **et son namespace** dans les métadonnées de chiffrement (authenticated data). Un secret chiffré pour `staybook-dev` ne peut pas être déchiffré dans `staybook-prod`.

---

## Partie 4 — De git push à la prod

### Question 29. Découpage CI / CD et accès au cluster
```
[Développeur] 
      │ git push (staybook-src)
      ▼
┌───────────── CI ─────────────┐
│ 1. Build de l'image          │
│ 2. Push sur ghcr.io          │
└──────────────┬───────────────┘
               │ 3. Commit du nouveau tag dans staybook-gitops
┌───────────── CD ─────────────┐
│ 4. Pull Request vers prod    │
│ 5. Déploiement par Argo CD   │
└──────────────────────────────┘
```
- **Accès au cluster** : Un accès au cluster n'est requis qu'à l'étape 5, et il est détenu **exclusivement par Argo CD** opérant à l'intérieur du cluster.
- GitHub Actions n'a **jamais besoin de kubeconfig** ni d'accès réseau au cluster (modèle Pull).

### Question 30. Rôles des jobs, tokens et multi-plateformes
- `build-push` est la **CI** (construction de l'artéfact logiciel). Il utilise `GITHUB_TOKEN` car il publie sur le registre GitHub Packages du même compte.
- `update-gitops` est le **CD** (publication de la configuration d'infrastructure). Il nécessite `GITOPS_TOKEN` car il doit pousser un commit sur un autre dépôt (`staybook-gitops`).
- Le multi-plateforme (`linux/amd64,linux/arm64`) permet aux conteneurs de tourner nativement aussi bien sur les serveurs x86 que sur les puces ARM (Apple Silicon, serveurs AWS Graviton).

### Question 31. Sécurité des tokens (Moindre privilège)
- Token TP 1 : Donné à Argo CD en lecture seule (`Contents: Read`).
- Token TP 2 : Donné à la CI en lecture/écriture (`Contents: Read and write`) limité au dépôt `staybook-gitops`.
- En cas de compromission du token CI, l'attaquant ne peut que modifier les manifests de `staybook-gitops`. Il ne dispose d'aucun accès au cluster Kubernetes ni aux autres dépôts de l'organisation.

### Question 32. Impact d'une image privée et résilience du cluster
- Si l'image restait privée, le kubelet échouerait à la télécharger avec l'erreur `ErrImagePull` / `ImagePullBackOff`.
- Le site reste disponible pendant ce temps car Kubernetes applique une stratégie de déploiement progressif (`RollingUpdate`) : les anciens pods restent en service tant que les nouveaux pods ne sont pas déclarés prêts (`Ready`).

### Question 33. Chaîne complète du git push au déploiement en dev
1. Commit & push sur `staybook-src` (`front/public/index.html`).
2. GitHub Actions déclenche le job de CI, compile l'image et la publie sur `ghcr.io/nicochlebo/staybook-front:sha-<tag>`.
3. Le second job met à jour `overlays/dev/kustomization.yaml` dans `staybook-gitops` avec le nouveau SHA et le pousse sur `main`.
4. Argo CD détecte le commit Git, constate la différence (OutOfSync) et déclenche la mise à jour automatique.
5. Le nœud kind tire directement la nouvelle image depuis le registre public `ghcr.io` via Internet (contrairement au `kind load` du TP 1 qui injectait l'image locale directement dans le runtime de conteneur).
6. Le port `8082` (prod) n'a pas changé car son overlay `overlays/prod/kustomization.yaml` pointe toujours sur son tag fixé.

### Question 34. Promotion en prod par Pull Request et zéro downtime
- **Pourquoi une PR en prod** : Pour assurer une validation humaine, une revue de code, une traçabilité d'audit et la conformité réglementaire avant livraison en production.
- **Règles GitHub** : Branch Protection Rules imposant :
  - L'interdiction du push direct sur `main`.
  - Au moins une revue et approbation par un pair.
  - Le passage obligatoire des tests automatisés.
- **Disponibilité du site** : Avec 2 réplicas et le RollingUpdate par défaut, Kubernetes met à jour un pod à la fois. Le service est resté disponible en continu sans interruption de service.

### Question 35. Rollback GitOps et option `-m 1`
- **Pourquoi `-m 1`** : Un commit de merge possède deux parents (parent 1 = la branche principale `main`, parent 2 = la branche fusionnée). L'option `-m 1` indique à Git de conserver la branche principale comme référence et d'inverser les modifications apportées par la branche mergée.
- **Comparaison des rollbacks** :
  - `argocd app rollback` : Modifie l'état du cluster de manière impérative. Avec la synchronisation automatique (`auto-sync`), Argo CD détecterait immédiatement une dérive et écraserait ce rollback pour réaligner le cluster sur l'état décrit dans Git.
  - `git revert` : Modifie directement la source de vérité (Git). Argo CD applique ensuite naturellement le retour arrière. C'est la **seule méthode autorisée et pérenne** en GitOps avec auto-sync.
