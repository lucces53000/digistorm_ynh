# DigiStorm pour YunoHost

Paquet communautaire indépendant des sources amont pour déployer [DigiStorm](https://codeberg.org/ladigitale/digistorm) sur YunoHost.

## Compatibilité et architecture

- DigiStorm amont **1.3.1**, épinglé par SHA-256 dans `manifest.toml`.
- YunoHost 12.1.40 ou ultérieur ; Node.js 24 est fourni par la ressource Node.js YunoHost.
- Redis dédié à cette instance, lié à `127.0.0.1`, protégé par un secret aléatoire et conservé avec les données de l’application ; le port est réservé par la ressource de port YunoHost. La configuration globale de Redis n’est pas modifiée.
- Les téléversements sous `static/fichiers` et les fichiers temporaires sont redirigés vers le répertoire de données persistant YunoHost.
- Nginx transmet les en-têtes WebSocket Socket.IO et DigiStorm continue de servir lui-même les assets statiques (`REVERSE_PROXY=0`).
- Cette version amont ne supporte pas les sous-chemins : choisir la racine `/` d’un domaine dédié. Le script d’installation refuse toute autre valeur.

## Installation

Depuis le gestionnaire d’applications YunoHost, installer ce paquet et choisir un domaine sans sous-chemin. Les dépendances système, Node, Redis, le service systemd et la configuration Nginx sont préparés par le paquet. La compilation Vite nécessite environ 3 Go de RAM libre et un accès réseau au registre npm pendant l’installation/la mise à niveau.

L’application n’a pas de configuration initiale du courrier dans le manifeste : Nodemailer tente le SMTP local `127.0.0.1:25`. Pour l’envoi des courriels (validation des comptes et réinitialisation de mot de passe), configurez un relais SMTP local fonctionnel ou ajustez les variables `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER` et `SMTP_PASSWORD` dans le fichier `$data_dir/.env`, puis redémarrez le service `digistorm`. Un échec de vérification SMTP est journalisé et ne bloque pas le démarrage, mais les courriels ne seront pas envoyés.

## Enregistrement LTI 1.3 avec Moodle

L’enregistrement dynamique doit être activé avec l’origine exacte de chaque plateforme Moodle, séparée par une virgule pour plusieurs instances. Exemple : `https://formadist.ynh.fr`. Utilisez uniquement le protocole et le domaine, sans chemin comme `/moodle`.

Cette valeur peut être saisie lors de l’installation dans **Origines Moodle autorisées**. Sur une installation existante, configurez-la avec :

```bash
yunohost app setting digistorm lti_platform_origins -v "https://formadist.ynh.fr"
yunohost app upgrade digistorm -u "https://github.com/lucces53000/digistorm_ynh"
```

La relance de l’application réécrit `AUTHORIZED_DOMAINS` avec le domaine DigiStorm et les origines Moodle autorisées. Dans Moodle, utilisez `https://digistorm.example.tld/lti/register` comme URL d’outil externe.

## Sauvegardes

YunoHost sauvegarde le code installé, le répertoire de données (fichiers téléversés, Redis AOF/RDB et secrets) et les configurations Nginx/systemd. Redis est persisté avant l’archivage, puis l’unité est arrêtée et relancée par un trap à la fin du script si elle était active.

## Développement et validation

Le manifeste épingle l’archive source Codeberg ; les scripts de cycle de vie se trouvent dans `scripts/` et les modèles de service/proxy dans `conf/`. Pour les tests d’installation réels, exécuter le paquet sur un serveur YunoHost 12.1.40+ dans un environnement de test approprié.

DigiStorm est distribué sous licence AGPL-3.0. Ce paquet YunoHost n’est pas affilié à La Digitale.
