Import-Module "$PSScriptRoot\vendor\PowerYaml\PowerYaml.psm1" -Force

$ConfigurationFile="$PSScriptRoot\configuration.yml"

$config = Get-Yaml -FromFile (Resolve-Path $ConfigurationFile)

$statutApplication = "OK"
$mail = "<h1>Anomalie d�tect�e sur l'application $nomApplication en environnement $environnementApplication</h1>"
$slackText = ""
$serveurApplication = ""
[System.Collections.ArrayList] $facts = @()

if($config.ContainsKey("serveurs") -and ($config.serveurs.count -ge 1)) {
    foreach($serveur in $config.serveurs) {
        [System.Collections.ArrayList] $monitorings = @()
        $serveurApplication += " $($serveur.name)"
        $mail += "<table><caption>Objets monitor�s sur le serveur $($serveur.name)</caption><thead><tr><th>Nom</th><th>valeur</th><th>statut<th></tr></thead><tbody>"

        foreach($disque in $serveur.disques) {
            try {
                $disqueWmi = Get-WmiObject -Query "select * from Win32_LogicalDisk where name='${disque}:'" -ComputerName $($serveur.name) -ErrorAction Stop
                $taille = [math]::round($disqueWmi.freespace / (1024*1024*1024), 1) 
                $percent = [math]::round($disqueWmi.freespace * 100 / $disqueWmi.size, 1)
                $statut = "OK"
                if($percent -lt $serveur.disquewarning) {
                    $statut = "KO"
                    $statutApplication = "KO"
                }
                $monitorings.Add(@{"name" = "disque ${disque}"; "value" = "${percent} % libre (${taille} Go) => $statut"}) | Out-Null
                $slackText += "disque ${disque} : ${percent} % libre (${taille} Go) => $statut`n"
                $mail += "<tr><td>disque ${disque}</td><td>${percent} % libre (${taille} Go)</td><td>$statut</td></tr>"
            } catch {
                $statut = "KO"
                $statutApplication = "KO"              
                $monitorings.Add(@{"name" = "disque ${disque}"; "value" = "Impossible de se connecter au serveur"}) | Out-Null
                $slackText += "disque ${disque} : Impossible de se connecter au serveur => $statut`n"
                $mail += "<tr><td>disque ${disque}</td><td>Impossible de se connecter au serveur</td><td>$statut</td></tr>"
            }
        }
        try {
            $system = Get-Ciminstance Win32_OperatingSystem -ComputerName $($serveur.name) -ErrorAction Stop
            $freeMemory = [math]::Round($system.FreePhysicalMemory * 100 / $system.TotalVisibleMemorySize,2)
            $taille = [math]::round($system.FreePhysicalMemory / (1024*1024), 1) 
            $statut = "OK"
            if($freeMemory -lt $memoryWarning) {
                $statut = "KO"
                $statutApplication = "KO"
            }
            $monitorings.Add(@{"name" = "m�moire"; "value" = "${freeMemory} % libre (${taille} Go) => $statut"}) | Out-Null
            $slackText += "m�moire : ${freeMemory} % libre (${taille} Go) => $statut`n"
            $mail += "<tr><td>m�moire</td><td>${freeMemory} % libre (${taille} Go)</td><td>$statut</td></tr>"
        } catch {
            $statut = "KO"
            $statutApplication = "KO"
            $monitorings.Add(@{"name" = "m�moire"; "value" = "Impossible de se connecter au serveur"}) | Out-Null
            $slackText += "m�moire : Impossible de se connecter au serveur => $statut`n"
            $mail += "<tr><td>m�moire</td><td>Impossible de se connecter au serveur</td><td>$statut</td></tr>"
        }

        foreach($process in $serveur.processus) {
            try {
                $getProcess = Get-Process $process.name -ErrorAction SilentlyContinue -ComputerName $($serveur.name)
                $statut = "OK"
                switch ($process.comparator) {
                    "=" { 
                        if($getProcess.count -ne $process.number) {
                            $statut = "KO"
                            $statutApplication = "KO"
                        }
                    }
                    "<" {
                        if($getProcess.count -ge $process.number) {
                            $statut = "KO"
                            $statutApplication = "KO"
                        }
                    }
                    ">" {
                        if($getProcess.count -le $process.number) {
                            $statut = "KO"
                            $statutApplication = "KO"
                        }
                    }
                    "<=" {
                        if($getProcess.count -gt $process.number) {
                            $statut = "KO"
                            $statutApplication = "KO"
                        }
                    }
                    ">=" {
                        if($getProcess.count -lt $process.number) {
                            $statut = "KO"
                            $statutApplication = "KO"
                        }
                    }
                }
                $monitorings.Add(@{"name" = "Processus $($process.name)"; "value" = "$($getProcess.count) en cours (doit �tre $($process.comparator) � $($process.number)) => $statut"}) | Out-Null
                $slackText += "Processus $($process.name) : $($getProcess.count) en cours (doit �tre $($process.comparator) � $($process.number)) => $statut`n"
                $mail += "<tr><td>Processus $($process.name)</td><td>$($getProcess.count) en cours (doit �tre $($process.comparator) � $($process.number))</td><td>$statut</td></tr>"
            } catch {
                $monitorings.Add(@{"name" = "Processus $($process.name)"; "value" = "Impossible de se connecter au serveur"}) | Out-Null
                $slackText += "Processus $($process.name) : Impossible de se connecter au serveur => $statut`n"
                $mail += "<tr><td>Processus $($process.name)</td><td>Impossible de se connecter au serveur</td><td>$statut</td></tr>"
            }
        }
        $mail += "</tbody></table>"
        $facts.Add(@{"title" = "Objets monitor�s de $($serveur.name)"; "facts" = $monitorings}) | Out-Null
    }
}

if($config.ContainsKey("restcall") -and ($config.restcall.count -ge 1)) {
    $mail += "<ul>"
    [System.Collections.ArrayList] $monitorings = @()
    foreach($restcall in $config.restcall) {
        $statut = "OK"
        Try {
            $StartDate=(Get-Date)
            $response = Invoke-RestMethod -Uri $restcall.url -Method Get
            $EndDate=(Get-Date)
            $duration = $(New-TimeSpan -Start $StartDate -End $EndDate).TotalSeconds
            switch ($restcall.response.type) {
                "property" {  
                    if((![bool]($response.PSobject.Properties.name -match $restcall.response.name)) -or (!$response.PSobject.Properties.Match($restcall.response.name).Value -eq $restcall.response.value)) {
                        $statut = "KO"
                        $statutApplication = "KO"
                    }
                }
                "body" {
                    if(!($response -match $restcall.response.value)) {
                        $statut = "KO"
                        $statutApplication = "KO"    
                    }
                }
                Default {
                    $statut = "KO"
                    $statutApplication = "KO"    
                }
            }
            if($duration -gt $restcall.maxDurationSeconds) {
                $statut = "KO"
                $statutApplication = "KO"
            }
        } Catch {
            $statut = "KO"
            $statutApplication = "KO"    
        }
        $mail += "<li>$($restcall.name) ($duration secondes) : $statut</li>"
        $slackText += "$($restcall.name) ($duration secondes) : $statut`n"
        $monitorings.Add(@{"name" = "$($restcall.name) ($duration secondes)"; "value" = $statut}) | Out-Null
    }
    $mail += "<ul>"
    $facts.Add(@{"title" = "Test disponibilit� de services REST"; "facts" = $monitorings}) | Out-Null
}

$slackIcon = ":x:"
if($statutApplication -eq "OK") {
    $mail = $mail.Replace("Anomalie", "Aucune anomalie")
    $slackText = $slackText.Replace("Anomalie", "Aucune anomalie")
    $slackIcon = ":white_check_mark:"
}

$requestBody = @{
    "configuration" = @{
        "url-teams-ok" = $config.urlmicrosoftteams.ok
        "url-teams-ko" = $config.urlmicrosoftteams.ko
        "destinataire-mail" = $config.destinatairemail
    }
    "application" = @{
        "nom-application" = $config.application.nom
        "environnement-application" = $config.application.environnement
        "serveur-application" = $serveurApplication
        "statut-application" = $statutApplication
    }
    "sections" = $facts
    "corps-mail" = $mail
    "slack" = @{
        "slack-url" = $config.urlslack
        "slack-username" = "$($config.application.nom) $statutApplication ($($config.application.environnement))"
        "slack-text" = $slackText
        "slack-icon-emoji"= $slackIcon
    }
}
Invoke-RestMethod -Uri $config.urlmicrosoftflow -Method Post -ContentType "Application/json" -Body $(ConvertTo-Json $requestBody -Depth 10)
