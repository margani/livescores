$ShouldEscapeCharacters = @('_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!')
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0"
$EventStatusIcons = @{
    "NotStarted" = "🕒"
    "HalfTime"   = "⏸"
    "FullTime"   = "🏁"
    "Unknown"    = "❓"
}
$EventStatusName = @{
    "NS"      = "NotStarted"
    "HT"      = "HalfTime"
    "FT"      = "FullTime"
    "Unknown" = "Unknown"
}
$DataFilePath = "./src/data.json"
Function Get-Data() { return Get-Content -Path $DataFilePath -Raw | ConvertFrom-Json }
Function Save-Data($Data) { $Data | ConvertTo-Json -Depth 100 | Set-Content -Path $DataFilePath }
Function Get-LeagueById($Id) {
    $data = Get-Data
    return $data.leagues | Where-Object { $_.Id -eq $Id }
}
Function Get-TeamById($Id) {
    $data = Get-Data
    return $data.teams | Where-Object { $_.Id -eq $Id }
}
Function Add-EventLeague($Data, $TodayEvent) {
    if (!($Data.leagues | Where-Object { $_.Id -eq $TodayEvent.League.Id })) {
        $Data.leagues += $TodayEvent.League
    }
}
Function Add-EventTeams($Data, $TodayEvent) {
    if (!($Data.teams | Where-Object { $_.Id -eq $TodayEvent.HomeTeam.Id })) {
        $Data.teams += $TodayEvent.HomeTeam
    }

    if (!($Data.teams | Where-Object { $_.Id -eq $TodayEvent.AwayTeam.Id })) {
        $Data.teams += $TodayEvent.AwayTeam
    }
}
Function Test-EventIsIncluded($Data, $TodayEvent) {
    $isMatch = $false
    $league = $TodayEvent.League
    $Data.filters | ForEach-Object {
        $filter = $_

        if ($filter.teams -and `
            ($filter.teams -contains $TodayEvent.HomeTeam.Name -or `
                    $filter.teams -contains $TodayEvent.AwayTeam.Name)) {
            $isMatch = $true
            return
        }

        if ($filter.league -and $filter.league -eq $league.Name -and $filter.country -eq $league.Country) {
            $isMatch = $true
            return
        }
    }

    return $isMatch
}
Function Get-League($Stage) {
    return @{
        Id          = $Stage.Sid
        Name        = $Stage.Snm
        BadgeUrl    = "https://static.livescore.com/competition/high/$($Stage.badgeUrl)"
        Country     = $Stage.Cnm
        Slug        = $Stage.Scd
        CountrySlug = $Stage.Ccd
    }
}
Function Get-StageEvent($Stage, $StageEvent) {
    $league = Get-League -Stage $Stage
    $homeTeam = $StageEvent.T1[0]
    $awayTeam = $StageEvent.T2[0]
    return @{
        League    = $league
        Id        = $StageEvent.Eid
        HomeTeam  = @{
            Id           = $homeTeam.ID
            Name         = $homeTeam.Nm
            Abbreviation = $homeTeam.Abr
            LogoUrl      = "https://lsm-static-prod.livescore.com/medium/$($homeTeam.Img)"
        }
        AwayTeam  = @{
            Id           = $awayTeam.ID
            Name         = $awayTeam.Nm
            Abbreviation = $awayTeam.Abr
            LogoUrl      = "https://lsm-static-prod.livescore.com/medium/$($awayTeam.Img)"
        }
        HomeScore = $StageEvent.Tr1
        AwayScore = $StageEvent.Tr2
        StartTime = [datetime]::ParseExact($StageEvent.Esd, "yyyyMMddHHmmss", $null)
        Status    = Get-EventStatus($StageEvent.Eps)
        MessageId = $null
    }
}
Function Get-TodayEvents() {
    $today = Get-Date -Format "yyyyMMdd"
    $url = "https://prod-public-api.livescore.com/v1/api/app/date/soccer/$today/0"
    $response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck

    $todayData = $response.Content | ConvertFrom-Json
    $events = @()
    $todayData.Stages | ForEach-Object {
        $stage = $_
        $stage.Events | Where-Object { $_.T1 -and $_.T2 } | ForEach-Object {
            $events += Get-StageEvent -Stage $stage -StageEvent $_
        }
    }
    return $events
}
Function Get-EventStatus($Status) {
    switch ($Status) {
        { ($_ -eq "NS") -or ($_ -eq "HT") -or ($_ -eq "FT") } { return $EventStatusName[$Status] }
        default { return $Status }
    }
}
Function Get-IsEventLive($Status) {
    return $Status -ne "NotStarted" -and $Status -ne "FullTime"
}
Function Get-IncidentType($Incident) {
    switch ($Incident.IT) {
        36 { return "⚽" }
        37 { return "P⚽" }
        38 { return "PM" }
        39 { return "O⚽" }
        40 { return "PSM" }
        41 { return "PS⚽" }
        43 { return "🟨" }
        44 { return "🟥" }
        45 { return "🟨🟨>🟥" }
        47 { return "OT⚽" }
        62 { return "VAR" }
        63 { return "A" }
        default { return "Unknown incident type, [#$($Incident.Eid)] type [$($Incident.IT)] at minute [$($Incident.Min),$($Incident.MinEx)]" }
    }
}
Function Get-EventIncidents($EventId) {
    Write-Host "Getting event incidents $EventId"
    $url = "https://prod-public-api.livescore.com/v1/api/app/incidents/soccer/$EventId"
    $response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck

    $eventData = $response.Content | ConvertFrom-Json
    if (!$eventData -or $response.Content -eq "{}") {
        Write-Host "No event data found at url: $url"
        return $()
    }

    $incidents = @()
    $eventData.Incs.PSObject.Properties | ForEach-Object {
        $half = $_.Name
        Write-Host " - Half: $half"
        $_.Value | ForEach-Object {
            $inc = $_
            Write-Host "  - Minute: $($inc.Min) Type: $($inc.IT) Player: $($inc.Pn) Reason: $($inc.IR)"
            $homeScore = $null
            $awayScore = $null
            if ($inc.Sc) {
                $homeScore = $inc.Sc[0]
                $awayScore = $inc.Sc[1]
            }

            $minute = $inc.Min.ToString()
            if ($inc.MinEx) {
                $minute += " + $($inc.MinEx.ToString())"
            }

            $secondChild = $null
            if ($inc.Incs) {
                $inc = $inc.Incs[0]
                if ($inc.Incs.Length -gt 1) {
                    $secondChild = $inc.Incs[1]
                }
            }

            $assist = $null
            if ($secondChild) {
                $assist = $secondChild.Pn
            }

            $incidents += @{
                IsHome    = $inc.Nm -eq "1"
                IsAway    = $inc.Nm -eq "2"
                Half      = $half
                Minute    = $minute
                Type      = Get-IncidentType($inc)
                Reason    = $inc.IR
                HomeScore = $homeScore
                AwayScore = $awayScore
                Player    = @{
                    Name      = $inc.Pn
                    FirstName = $inc.Fn
                    LastName  = $inc.Ln
                }
                Assist    = $assist
            }
        }
    }

    return $incidents
}
Function Get-EventDetails($Id) {
    $url = "https://prod-public-api.livescore.com/v1/api/app/scoreboard/soccer/$Id"
    $response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck

    return $response.Content | ConvertFrom-Json
}
Function Get-EventHighlight($EventId) {
    $url = "https://prod-cdn-media-api.livescore.com/api/v1/event/$EventId"
    $response = Invoke-WebRequest -Uri $url -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck

    $eventMedia = $response.Content | ConvertFrom-Json
    if (!$eventMedia -or $response.Content -eq "{}" -or !$eventMedia.sections -or !$eventMedia.sections.Length) {
        return $null
    }

    $video = $eventMedia.sections.videoPlaylist

    if (!$video -or $video.type -ne "YOUTUBE") {
        Write-Host "Unknown video type [$($video.type)] of event [$EventId]"
        return $null
    }

    $media = $video.items | Select-Object -First 1
    return @{
        ThumbnailUrl = $media.thumbnailUrl
        VideoUrl     = "https://www.youtube.com/watch?v=$($media.streamId)"
        PublishedAt  = Get-Date -UnixTime ($media.publishedAt / 1000)
        MessageId    = $null
    }
}
Function Send-LeagueTables() {
    $Data = Get-Data
    $Data.leagues | ForEach-Object {
        $league = $_
        $tableImageFilePath = "./generated/table-$($league.Id).png"

        if (!(Test-Path -Path $tableImageFilePath)) {
            return
        }

        Send-PhotoByFile -PhotoFilePath $tableImageFilePath -Caption "🏆 $($league.Country) - $($league.Name)" | Out-Null
    }
}
Function Update-Leagues() {
    $Data = Get-Data
    $Data.leagues | Where-Object { !$_.Slug } | ForEach-Object {
        $league = $_
        Write-Host "Updating slug for league: $($league.Name)"
        $leagueFirstEvent = $Data.events | Where-Object { $_.League -eq $league.Id } | Select-Object -First 1
        $eventDetails = Get-EventDetails -Id $leagueFirstEvent.Id

        Add-MemberIfNotExist -Object $league -Name Slug -Value $eventDetails.Stg.Scd
        Add-MemberIfNotExist -Object $league -Name CountrySlug -Value $eventDetails.Stg.Ccd
    }
    Save-Data -Data $Data
}
Function Repair-Data() {
    $Data = Get-Data
    $Data.events | ForEach-Object {
        $savedEvent = $_

        $te = $savedEvent | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $te.League = Get-LeagueById -Id $savedEvent.League
        $te.HomeTeam = Get-TeamById -Id $savedEvent.HomeTeam
        $te.AwayTeam = Get-TeamById -Id $savedEvent.AwayTeam
        $isMatch = Test-EventIsIncluded -Data $Data -TodayEvent $te
        if (!$isMatch -and $savedEvent.Status -ne "FullTime") {
            $Data.events = $Data.events | Where-Object { $_.Id -ne $savedEvent.Id }
        }
    }

    $Data.teams | Where-Object {
        $team = $_
        -not( $Data.events | Where-Object { $team.Id -eq $_.HomeTeam -or $team.Id -eq $_.AwayTeam })
    } | ForEach-Object {
        $team = $_
        $Data.teams = $Data.teams | Where-Object { $_.Id -ne $team.Id }
    }

    $Data.leagues | Where-Object {
        $league = $_
        -not( $Data.events | Where-Object { $league.Id -eq $_.League })
    } | ForEach-Object {
        $league = $_
        $Data.leagues = $Data.leagues | Where-Object { $_.Id -ne $league.Id }
    }

    Save-Data -Data $Data
}
Function Send-TodayEvents() {
    $Data = Get-Data
    $eventsToSend = @()
    Get-TodayEvents | ForEach-Object {
        $te = $_
        $se = $Data.events | Where-Object { $_.Id -eq $te.Id }
        if (!$se) {
            $isMatch = Test-EventIsIncluded -Data $Data -TodayEvent $te
            if ($isMatch) {
                $eventsToSend += $te
                Add-EventLeague -Data $Data -TodayEvent $te
                Add-EventTeams -Data $Data -TodayEvent $te
                Save-Data -Data $Data
            }
        }
    }

    $eventMessage = ""
    $eventsToSend.League.Id | Sort-Object -Unique | ForEach-Object {
        $leagueId = $_
        $events = $eventsToSend | Where-Object { $_.League.Id -eq $leagueId }
        $league = $events | Select-Object -First 1 -ExpandProperty League
        $eventMessage += "🏆 $($league.Country) \- $($league.Name)`n"
        $events | ForEach-Object {
            $te = $_

            $message = Get-EventAsMessage -TodayEvent $te
            $eventMessage += "$message`n"
            $Data.events += @{
                Id        = $te.Id
                League    = $te.League.Id
                HomeTeam  = $te.HomeTeam.Id
                AwayTeam  = $te.AwayTeam.Id
                HomeScore = $te.HomeScore
                AwayScore = $te.AwayScore
                StartTime = $te.StartTime
                Status    = $te.Status
                MessageId = $null
            }
        }
        $eventMessage += "`n"
    }

    try {
        if ($eventMessage) {
            $eventMessage = "📅 $(Get-Date -Format "dddd, dd MMMM yyyy")`n`n" + $eventMessage
            Write-Host "Sending message..."
            Send-Message -Message $eventMessage | Out-Null
        }

        Save-Data -Data $Data
    }
    catch {
        Write-Host $_.Exception.Message
        throw
    }
}
Function Update-SavedEvent($Data, $Id) {
    $se = $Data.events | Where-Object { $_.Id -eq $Id }
    if (!$se) {
        return
    }
    $evDetails = Get-EventDetails -Id $Id
    $se.HomeScore = $evDetails.Tr1
    $se.AwayScore = $evDetails.Tr2
    $se.Status = Get-EventStatus -Status $evDetails.Eps
    Save-Data -Data $Data
    return $se
}
Function Send-SavedEvent($Data, $SavedEvent) {
    if (!$SavedEvent -or $SavedEvent.MessageId) {
        return
    }

    if ($SavedEvent.Status -eq "FullTime") {
        Write-Host "Sending event $($SavedEvent.Id) message"
        $incidents = Get-EventIncidents -EventId $SavedEvent.Id
        $message = Get-FullEventAsMessage -SavedEvent $SavedEvent -Incidents $incidents
        if ($message) {
            $SavedEvent.MessageId = Send-Message -Message $message
            Save-Data -Data $Data
        }
    }
}
Function Send-TodayFullTimeEvents() {
    $Data = Get-Data
    Get-TodayEvents | ForEach-Object {
        $se = Update-SavedEvent -Data $Data -Id $_.Id
        Send-SavedEvent -Data $Data -SavedEvent $se
    }
}
Function Send-AllFullTimeEvents() {
    $Data = Get-Data
    $Data.events | ForEach-Object {
        $se = Update-SavedEvent -Data $Data -Id $_.Id
        Send-SavedEvent -Data $Data -SavedEvent $se
    }
}
Function Send-EventsHighlights() {
    $Data = Get-Data
    $Threshold = (Get-Date).AddDays(-7)
    $Data.events | Where-Object { !$_.Highlight -and $_.MessageId -and $_.StartTime -ge $Threshold } | ForEach-Object {
        Send-EventHighlight -Data $Data -SavedEvent $_
    }
}
Function Send-EventHighlight($SavedEvent) {
    $homeTeam = Get-TeamById -Id $SavedEvent.HomeTeam
    $awayTeam = Get-TeamById -Id $SavedEvent.AwayTeam

    $highlight = Get-EventHighlight -EventId $SavedEvent.Id
    Add-MemberIfNotExist -Object $SavedEvent -Name Highlight -Value $highlight
    if (!$SavedEvent.Highlight) {
        return
    }

    $caption = "*$(Get-EscapedText($homeTeam.Name))* $($SavedEvent.HomeScore)\-$($SavedEvent.AwayScore) *$(Get-EscapedText($awayTeam.Name))*"
    $SavedEvent.Highlight.MessageId = Send-Message `
        -Message $caption `
        -ReplyToMessageId $SavedEvent.MessageId `
        -Url (Get-EscapedText($SavedEvent.Highlight.VideoUrl))
    Save-Data -Data $Data
}
Function Get-EventAsMessage($TodayEvent) {
    $homeTeam = $TodayEvent.HomeTeam
    $awayTeam = $TodayEvent.AwayTeam
    $time = $TodayEvent.StartTime.ToString("HH:mm")

    $icon = $EventStatusIcons[$TodayEvent.Status]
    if (!$icon) {
        $icon = "⚽"
    }

    return "$icon $time *$(Get-EscapedText($homeTeam.Name))* 🆚 *$(Get-EscapedText($awayTeam.Name))*"
}
Function Get-FullEventAsMessage($SavedEvent, $Incidents) {
    $homeTeam = Get-TeamById -Id $SavedEvent.HomeTeam
    $awayTeam = Get-TeamById -Id $SavedEvent.AwayTeam
    $lineLength = 45

    $icon = $EventStatusIcons[$SavedEvent.Status]
    if ($icon) { $icon += " " }

    $league = Get-LeagueById -Id $SavedEvent.League
    $message = "📅 $(Get-Date -Format "dddd, dd MMMM yyyy")`n`n"
    $message += "🏆 $($league.Country) \- $($league.Name)`n"
    $message += "$icon *$(Get-EscapedText($homeTeam.Name))* $($SavedEvent.HomeScore)\-$($SavedEvent.AwayScore) *$(Get-EscapedText($awayTeam.Name))*`n``````"
    $maxMinuteWidth = ($Incidents | ForEach-Object { "$(Get-EscapedText($_.Minute))".Length } | Measure-Object -Maximum).Maximum
    $eachLength = ($lineLength - $maxMinuteWidth - 1) / 2
    $Incidents | ForEach-Object {
        $inc = $_
        $playerName = $inc.Player.LastName
        if ($inc.Player.FirstName) {
            $playerName = "$($inc.Player.FirstName[0]). $playerName"
        }

        $line = "$($inc.Type) $(Get-EscapedText($playerName))"
        if ($line.Length -gt ($eachLength - 3)) {
            $line = $line.Substring(0, $eachLength - 3) + "..."
        }
        $minute = "$(Get-EscapedText($inc.Minute))'".PadRight($maxMinuteWidth, " ")

        if ($inc.IsHome) {
            $line = $line.PadRight($eachLength, " ")
        }
        else {
            $line = "".PadLeft($eachLength, " ") + $line.PadRight($eachLength, " ")
        }
        $message += "`n$minute $line"
    }
    $message += "`n``````"

    return $message
}
Function Send-Message($Message, $ReplyToMessageId = $null, $Url = $null) {
    $body = @{
        text                 = $Message
        parse_mode           = "MarkdownV2"
        reply_to_message_id  = $ReplyToMessageId
        link_preview_options = "{`"is_disabled`": false, `"url`": `"$Url`"}"
    }

    if (!$Url) {
        $body.Remove("link_preview_options")
    }

    return Send-TelegramAPIJson -Action "sendMessage" -Body $body
}
Function Send-PhotoByUrl($PhotoUrl, $Caption, $ReplyToMessageId = $null) {
    return Send-TelegramAPIJson -Action "sendPhoto" -Body @{
        photo               = $PhotoUrl
        caption             = $Caption
        reply_to_message_id = $ReplyToMessageId
    }
}
Function Send-TelegramAPIJson($Action, $Body) {
    try {
        Add-MemberIfNotExist -Object $Body -Name chat_id -Value "$env:CHAT_ID"
        Add-MemberIfNotExist -Object $Body -Name parse_mode -Value "MarkdownV2"

        $Url = "https://api.telegram.org/bot$($env:BOT_TOKEN)/$Action"
        $Body = $Body | ConvertTo-Json -Depth 100

        $response = Invoke-WebRequest -Uri $Url -Body $Body -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck -Method Post -ContentType "application/json"
        $result = $response.Content | ConvertFrom-Json
        if (!$result.ok) {
            Write-Host $result
            $Body | Write-Host
            throw "Error sending $Action."
        }

        Write-Host "$Action is done successfully."
        return $result.result.message_id
    }
    catch {
        Write-Host "Error doing $($Action):"
        Write-Host $_
    }
}
Function Send-PhotoByFile($PhotoFilePath, $Caption, $ReplyToMessageId = $null) {
    return Send-TelegramAPIFormData -Action "sendPhoto" -Body @{
        photo               = Get-Item -LiteralPath $PhotoFilePath
        caption             = $Caption
        reply_to_message_id = $ReplyToMessageId
    }
}
Function Send-TelegramAPIFormData($Action, $Body, $FilePropertyName, $FilePath) {
    try {
        Add-MemberIfNotExist -Object $Body -Name parse_mode -Value "MarkdownV2"

        $Url = "https://api.telegram.org/bot$($env:BOT_TOKEN)/$($Action)?chat_id=$($env:CHAT_ID)"
        $response = Invoke-RestMethod -Uri $Url -Method Post -Form $Body -SkipCertificateCheck -SkipHeaderValidation -SkipHttpErrorCheck
        if (!$response.ok) {
            Write-Host $response
            throw "Error sending $Action."
        }

        Write-Host "$Action is done successfully."
        return $response.result.message_id
    }
    catch {
        Write-Host "Error doing $($Action):"
        Write-Host $_
    }
}
Function Get-EscapedText($Value) {
    $text = $value.ToString()

    foreach ($char in $ShouldEscapeCharacters) {
        $text = $text -replace [regex]::Escape($char), "\$char"
    }

    return $text
}
Function Add-MemberIfNotExist($Object, $Name, $Value = $null) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}
