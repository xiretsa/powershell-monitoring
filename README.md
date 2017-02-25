# power-monitoring
================

## Description

Module powershell permettant de monitorer un serveur eet d'envoyer le résultat en effectuant un appel REST vers Microsoft Flow.

L'appel permet dans flow d'envoyer un mail, créer un message dans Teams et créer un message dans slack

Vérifie :
 - Les espaces disques
 - La mémoire RAM
 - La présence de processus
 - L'appel à des services REST

Le module a besoin de [PowerYaml](https://github.com/scottmuc/PowerYaml) pour lire la configuration.
Pour cela cloner le projet dans un répertoire vendor stocké avec ce script.

## Configuration

Le fichier de configuration est en Yaml doit être sous la forme :
```YAML
urlmicrosoftflow: "Url appel REST de flow"
urlmicrosoftteams:
  ok: "Url webhook teams si appli OK"
  ko: "Url webhook teams si appli KO"
urlslack: "Url slack"
destinatairemail: "adresse mail destinataire"
application:
  nom: "Nom de l'application"
  environnement: "Environnement de l'application"
serveurs:
  - name: "Nom du premier serveur à monitorer"
    disques:                           # Lettre des lecteurs de disque à vérifier
      - C
      - E
    disquewarning: 10                  # limite d'espace disque libre en pourcentage en dessous de laquelle signaler en anomalie
    memorywarning: 15                  # limite de mémoire libre en pourcentage en dessous de laquelle signaler en anomalie
    processus:                         # Liste des processus à surveiller
      - name: svchost                  # nom du processus sans le .exe
        number: 3                      # Nombre d'occurrence nécessaire du processus
        comparator: "="                # Comparateur pour le nombre d'occurrence, supporte : =, <, >, <=, >=
restcall:
  - name: "Nom associé à l'appel"
    url: "URL à appeler"
    maxDurationSeconds: 10             # Nombre de secondes pour avoir la réponse, si l'appel met plus longtemps, ce sera signalé en anomalie
    response:                          # Test à faire sur la réponse
      type: property                   # Type de test à faire sur la réponse : property ou body
      name: success                    # si property, nom de la propriété du JSON reçu
      value: True                      # si property, valeur de la propriété attendue
  - name: "Nom associé à l'appel"
    url: "URL à appeler"
    maxDurationSeconds: 10
    response:
      type: body
      value: OK                        # si body, chaîne de caractère faisant partie du corps de la réponse
```