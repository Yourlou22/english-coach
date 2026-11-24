# English AI Coach

Application iPhone personnelle d'apprentissage de l'anglais, avec une IA exécutée sur l'appareil. Projet en cours de conception ; ce dépôt ne contient que du code source.

État : squelette « Hello iPhone » (relevé de l'appareil et demande d'accès au micro).

## Compilation

Le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen) à partir de `project.yml`. Le workflow `.github/workflows/build-ios.yml` compile sans signature sur un exécuteur macOS de GitHub et publie un fichier `.ipa` non signé, à signer ensuite avec un Apple ID gratuit au moment de l'installation.

## Ce que ce dépôt ne contient pas

Ni données personnelles, ni clés ou secrets, ni poids de modèles d'IA.
