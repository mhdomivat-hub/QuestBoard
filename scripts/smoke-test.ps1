param(
    [string]$BaseUrl = "http://localhost",
    [string]$Username = "",
    [string]$Password = "",
    [string]$EnvFile = "",
    [string]$MemberUsername = "",
    [string]$MemberPassword = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[STEP] $Message"
}

function Write-Pass([string]$Message) {
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Parse-JsonOrFail {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Body
    )

    try {
        return $Body | ConvertFrom-Json
    }
    catch {
        Fail "$Label response is not valid JSON: $Body"
    }
}

function Ensure-ArrayOrFail {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($null -eq $Value) {
        Fail "$Label returned null JSON."
    }

    if ($Value -is [System.Array]) {
        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value)
    }

    Fail "$Label did not return a JSON array."
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match "^\s*$Key\s*="
    } | Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -split "=", 2)[1].Trim()
}

function Invoke-CurlJson {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Body,
        [string]$CookieIn,
        [string]$CookieOut,
        [Parameter(Mandatory = $true)][string]$TmpDir
    )

    $responseFile = Join-Path $TmpDir (([guid]::NewGuid().ToString()) + ".response")
    $args = @("-sS", "-X", $Method, "-o", $responseFile, "-w", "%{http_code}")

    if ($CookieOut) {
        $args += @("-c", $CookieOut)
    }
    if ($CookieIn) {
        $args += @("-b", $CookieIn)
    }

    if ($Body) {
        $payloadFile = Join-Path $TmpDir (([guid]::NewGuid().ToString()) + ".json")
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($payloadFile, $Body, $enc)
        $args += @("-H", "Content-Type: application/json", "--data-binary", "@$payloadFile")
    }

    $args += $Url
    $statusRaw = & curl.exe @args
    if (-not $?) {
        Fail "curl request failed for $Method $Url"
    }

    $status = 0
    if (-not [int]::TryParse(($statusRaw | Out-String).Trim(), [ref]$status)) {
        Fail "Could not parse HTTP status from curl output: $statusRaw"
    }

    $bodyText = ""
    if (Test-Path $responseFile) {
        $bodyText = Get-Content -Path $responseFile -Raw
    }

    return @{ Status = $status; Body = $bodyText }
}

function Assert-HttpStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Actual,
        [Parameter(Mandatory = $true)][int]$Expected,
        [string]$Body = ""
    )

    if ($Actual -ne $Expected) {
        Fail "$Label expected HTTP $Expected but got $Actual. Body: $Body"
    }
}

$base = $BaseUrl.TrimEnd("/")
$tmpDir = Join-Path $env:TEMP ("questboard-smoke-" + [guid]::NewGuid().ToString())
$cookieFile = Join-Path $tmpDir "cookies.txt"
$envPath = $EnvFile
if ([string]::IsNullOrWhiteSpace($envPath)) {
    $envPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) ".env"
}

if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Get-DotEnvValue -Path $envPath -Key "BOOTSTRAP_ADMIN_USERNAME"
}
if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = Get-DotEnvValue -Path $envPath -Key "BOOTSTRAP_ADMIN_PASSWORD"
}

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    Fail "Username/Password fehlen. Setze BOOTSTRAP_ADMIN_USERNAME/BOOTSTRAP_ADMIN_PASSWORD in $envPath oder uebergib -Username/-Password."
}

New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

try {
    Write-Step "Login against $base/api/login"
    $loginBody = @{ username = $Username; password = $Password } | ConvertTo-Json -Compress
    $login = Invoke-CurlJson -Method "POST" -Url "$base/api/login" -Body $loginBody -CookieOut $cookieFile -TmpDir $tmpDir

    if ($login.Status -ne 200) {
        Fail "Login failed with HTTP $($login.Status). Body: $($login.Body)"
    }

    $loginJson = Parse-JsonOrFail -Label "Login" -Body $login.Body

    if (-not $loginJson.token) {
        Fail "Login succeeded but token is missing in response."
    }
    Write-Pass "Login OK"

    Write-Step "GET $base/api/quests"
    $list = Invoke-CurlJson -Method "GET" -Url "$base/api/quests" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($list.Status -ne 200) {
        Fail "Quest list failed with HTTP $($list.Status). Body: $($list.Body)"
    }

    $listJson = Parse-JsonOrFail -Label "Quest list" -Body $list.Body
    $listArray = Ensure-ArrayOrFail -Label "Quest list" -Value $listJson
    Write-Pass "Quest list OK"
    Write-Step "GET $base/api/me"
    $me = Invoke-CurlJson -Method "GET" -Url "$base/api/me" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Me endpoint" -Actual $me.Status -Expected 200 -Body $me.Body
    $meJson = Parse-JsonOrFail -Label "Me endpoint" -Body $me.Body
    if (-not $meJson.userId -or -not $meJson.role) {
        Fail "Me endpoint missing userId/role. Body: $($me.Body)"
    }
    Write-Pass "Me endpoint OK"

    Write-Step "POST $base/api/quests"
    $questTitle = "Smoke Quest " + (Get-Date -Format "yyyyMMdd-HHmmss")
    $createBody = @{ title = $questTitle; description = "Automated smoke test"; status = "OPEN" } | ConvertTo-Json -Compress
    $create = Invoke-CurlJson -Method "POST" -Url "$base/api/quests" -Body $createBody -CookieIn $cookieFile -TmpDir $tmpDir
    if ($create.Status -ne 200) {
        Fail "Quest create failed with HTTP $($create.Status). Body: $($create.Body)"
    }

    $created = Parse-JsonOrFail -Label "Quest create" -Body $create.Body

    if (-not $created.id) {
        Fail "Quest create returned no id. Body: $($create.Body)"
    }
    Write-Pass "Quest create OK (id=$($created.id))"

    Write-Step "GET $base/api/quests/$($created.id)"
    $questGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($created.id)" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($questGet.Status -ne 200) {
        Fail "Quest detail failed with HTTP $($questGet.Status). Body: $($questGet.Body)"
    }
    $questGetJson = Parse-JsonOrFail -Label "Quest detail" -Body $questGet.Body
    if ($questGetJson.id -ne $created.id) {
        Fail "Quest detail id mismatch. Body: $($questGet.Body)"
    }
    if ($questGetJson.status -ne "OPEN") {
        Fail "New quest status expected OPEN. Body: $($questGet.Body)"
    }
    Write-Pass "Quest detail OK"

    Write-Step "GET $base/api/quests/$($created.id)/requirements (expect empty)"
    $reqListBefore = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($created.id)/requirements" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($reqListBefore.Status -ne 200) {
        Fail "Requirement list (before create) failed with HTTP $($reqListBefore.Status). Body: $($reqListBefore.Body)"
    }
    $reqListBeforeJson = Parse-JsonOrFail -Label "Requirement list before create" -Body $reqListBefore.Body
    $reqBeforeArray = Ensure-ArrayOrFail -Label "Requirement list before create" -Value $reqListBeforeJson
    if (@($reqBeforeArray).Count -ne 0) {
        Fail "Requirement list expected empty before create. Body: $($reqListBefore.Body)"
    }
    Write-Pass "Requirement list before create OK"

    Write-Step "POST $base/api/quests/$($created.id)/requirements"
    $reqBody = @{ itemName = "Smoke Item"; qtyNeeded = 10; unit = "pcs" } | ConvertTo-Json -Compress
    $reqCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/quests/$($created.id)/requirements" -Body $reqBody -CookieIn $cookieFile -TmpDir $tmpDir
    if ($reqCreate.Status -ne 200) {
        Fail "Requirement create failed with HTTP $($reqCreate.Status). Body: $($reqCreate.Body)"
    }

    $createdReq = Parse-JsonOrFail -Label "Requirement create" -Body $reqCreate.Body
    if (-not $createdReq.id) {
        Fail "Requirement create returned no id. Body: $($reqCreate.Body)"
    }
    Write-Pass "Requirement create OK (id=$($createdReq.id))"

    Write-Step "GET $base/api/quests/$($created.id)/requirements"
    $reqListAfterCreate = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($created.id)/requirements" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($reqListAfterCreate.Status -ne 200) {
        Fail "Requirement list (after create) failed with HTTP $($reqListAfterCreate.Status). Body: $($reqListAfterCreate.Body)"
    }
    $reqListAfterCreateJson = Parse-JsonOrFail -Label "Requirement list after create" -Body $reqListAfterCreate.Body
    $reqAfterCreateArray = Ensure-ArrayOrFail -Label "Requirement list after create" -Value $reqListAfterCreateJson
    $reqFromList = $reqAfterCreateArray | Where-Object { $_.id -eq $createdReq.id } | Select-Object -First 1
    if ($null -eq $reqFromList) {
        Fail "Created requirement not found in requirement list."
    }
    if ($reqFromList.collectedQty -ne 0 -or $reqFromList.deliveredQty -ne 0 -or $reqFromList.openQty -ne 10) {
        Fail "Initial requirement progress mismatch. Body: $($reqListAfterCreate.Body)"
    }
    Write-Pass "Requirement list after create OK"

    Write-Step "GET $base/api/requirements/$($createdReq.id)/contributions (expect empty)"
    $contribListBefore = Invoke-CurlJson -Method "GET" -Url "$base/api/requirements/$($createdReq.id)/contributions" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($contribListBefore.Status -ne 200) {
        Fail "Contribution list (before create) failed with HTTP $($contribListBefore.Status). Body: $($contribListBefore.Body)"
    }
    $contribListBeforeJson = Parse-JsonOrFail -Label "Contribution list before create" -Body $contribListBefore.Body
    $contribBeforeArray = Ensure-ArrayOrFail -Label "Contribution list before create" -Value $contribListBeforeJson
    if (@($contribBeforeArray).Count -ne 0) {
        Fail "Contribution list expected empty before create. Body: $($contribListBefore.Body)"
    }
    Write-Pass "Contribution list before create OK"

    Write-Step "POST $base/api/requirements/$($createdReq.id)/contributions"
    $contribBody = @{ qty = 3; status = "CLAIMED"; note = "smoke" } | ConvertTo-Json -Compress
    $contribCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/requirements/$($createdReq.id)/contributions" -Body $contribBody -CookieIn $cookieFile -TmpDir $tmpDir
    if ($contribCreate.Status -ne 200) {
        Fail "Contribution create failed with HTTP $($contribCreate.Status). Body: $($contribCreate.Body)"
    }

    $createdContrib = Parse-JsonOrFail -Label "Contribution create" -Body $contribCreate.Body
    if (-not $createdContrib.id) {
        Fail "Contribution create returned no id. Body: $($contribCreate.Body)"
    }
    if ($createdContrib.status -ne "CLAIMED") {
        Fail "Contribution create status expected CLAIMED. Body: $($contribCreate.Body)"
    }
    Write-Pass "Contribution create OK (id=$($createdContrib.id))"

    Write-Step "GET $base/api/requirements/$($createdReq.id)/contributions"
    $contribListAfterCreate = Invoke-CurlJson -Method "GET" -Url "$base/api/requirements/$($createdReq.id)/contributions" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($contribListAfterCreate.Status -ne 200) {
        Fail "Contribution list (after create) failed with HTTP $($contribListAfterCreate.Status). Body: $($contribListAfterCreate.Body)"
    }
    $contribListAfterCreateJson = Parse-JsonOrFail -Label "Contribution list after create" -Body $contribListAfterCreate.Body
    $contribAfterCreateArray = Ensure-ArrayOrFail -Label "Contribution list after create" -Value $contribListAfterCreateJson
    $contribFromList = $contribAfterCreateArray | Where-Object { $_.id -eq $createdContrib.id } | Select-Object -First 1
    if ($null -eq $contribFromList) {
        Fail "Created contribution not found in contribution list."
    }
    if ($contribFromList.status -ne "CLAIMED") {
        Fail "Contribution list expected CLAIMED status before update. Body: $($contribListAfterCreate.Body)"
    }
    Write-Pass "Contribution list after create OK"

    Write-Step "PATCH $base/api/contributions/$($createdContrib.id)/status"
    $contribPatchBody = @{ status = "DELIVERED" } | ConvertTo-Json -Compress
    $contribPatch = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($createdContrib.id)/status" -Body $contribPatchBody -CookieIn $cookieFile -TmpDir $tmpDir
    if ($contribPatch.Status -ne 200) {
        Fail "Contribution status update failed with HTTP $($contribPatch.Status). Body: $($contribPatch.Body)"
    }
    $patchedContrib = Parse-JsonOrFail -Label "Contribution status update" -Body $contribPatch.Body
    if ($patchedContrib.status -ne "DELIVERED") {
        Fail "Contribution status not updated to DELIVERED. Body: $($contribPatch.Body)"
    }
    Write-Pass "Contribution status update OK"

    Write-Step "GET $base/api/quests/$($created.id)/requirements (verify progress)"
    $reqListAfterDeliver = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($created.id)/requirements" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($reqListAfterDeliver.Status -ne 200) {
        Fail "Requirement list (after delivery) failed with HTTP $($reqListAfterDeliver.Status). Body: $($reqListAfterDeliver.Body)"
    }
    $reqListAfterDeliverJson = Parse-JsonOrFail -Label "Requirement list after delivery" -Body $reqListAfterDeliver.Body
    $reqAfterDeliverArray = Ensure-ArrayOrFail -Label "Requirement list after delivery" -Value $reqListAfterDeliverJson
    $reqDelivered = $reqAfterDeliverArray | Where-Object { $_.id -eq $createdReq.id } | Select-Object -First 1
    if ($null -eq $reqDelivered) {
        Fail "Requirement missing after delivery."
    }
    if ($reqDelivered.collectedQty -ne 3 -or $reqDelivered.deliveredQty -ne 3 -or $reqDelivered.openQty -ne 7) {
        Fail "Requirement progress mismatch after delivery. Body: $($reqListAfterDeliver.Body)"
    }
    Write-Pass "Requirement progress update OK"

    Write-Step "PATCH $base/api/quests/$($created.id)/status"
    $patchBody = @{ status = "DONE" } | ConvertTo-Json -Compress
    $patch = Invoke-CurlJson -Method "PATCH" -Url "$base/api/quests/$($created.id)/status" -Body $patchBody -CookieIn $cookieFile -TmpDir $tmpDir
    if ($patch.Status -ne 200) {
        Fail "Quest status update failed with HTTP $($patch.Status). Body: $($patch.Body)"
    }

    $patched = Parse-JsonOrFail -Label "Quest status update" -Body $patch.Body

    if ($patched.status -ne "DONE") {
        Fail "Quest status not updated to DONE. Body: $($patch.Body)"
    }
    Write-Pass "Quest status update OK"

    Write-Step "GET $base/api/quests/$($created.id) (verify DONE)"
    $questDone = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($created.id)" -CookieIn $cookieFile -TmpDir $tmpDir
    if ($questDone.Status -ne 200) {
        Fail "Quest detail after status update failed with HTTP $($questDone.Status). Body: $($questDone.Body)"
    }
    $questDoneJson = Parse-JsonOrFail -Label "Quest detail after status update" -Body $questDone.Body
    if ($questDoneJson.status -ne "DONE") {
        Fail "Quest detail did not return DONE status. Body: $($questDone.Body)"
    }
    Write-Pass "Quest detail after status update OK"

    Write-Step "NEGATIVE: GET $base/api/quests without cookie (expect 401)"
    $unauthList = Invoke-CurlJson -Method "GET" -Url "$base/api/quests" -TmpDir $tmpDir
    Assert-HttpStatus -Label "Unauthenticated quest list" -Actual $unauthList.Status -Expected 401 -Body $unauthList.Body
    Write-Pass "Unauthenticated quest list returns 401"

    Write-Step "NEGATIVE: PATCH quest status invalid value (expect 400)"
    $badQuestStatusBody = @{ status = "NOT_A_STATUS" } | ConvertTo-Json -Compress
    $badQuestStatus = Invoke-CurlJson -Method "PATCH" -Url "$base/api/quests/$($created.id)/status" -Body $badQuestStatusBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Invalid quest status" -Actual $badQuestStatus.Status -Expected 400 -Body $badQuestStatus.Body
    Write-Pass "Invalid quest status returns 400"

    Write-Step "NEGATIVE: PATCH contribution status invalid value (expect 400)"
    $tempInvalidContribBody = @{ qty = 1; status = "CLAIMED"; note = "invalid-status-check" } | ConvertTo-Json -Compress
    $tempInvalidContribCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/requirements/$($createdReq.id)/contributions" -Body $tempInvalidContribBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Create temp contribution for invalid status check" -Actual $tempInvalidContribCreate.Status -Expected 200 -Body $tempInvalidContribCreate.Body
    $tempInvalidContribCreateJson = Parse-JsonOrFail -Label "Create temp contribution for invalid status check" -Body $tempInvalidContribCreate.Body

    $badContribStatusBody = @{ status = "NOT_A_STATUS" } | ConvertTo-Json -Compress
    $badContribStatus = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($tempInvalidContribCreateJson.id)/status" -Body $badContribStatusBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Invalid contribution status" -Actual $badContribStatus.Status -Expected 400 -Body $badContribStatus.Body
    Write-Pass "Invalid contribution status returns 400"

    $missingQuestId = [guid]::NewGuid().ToString().ToUpper()
    Write-Step "NEGATIVE: GET missing quest (expect 404)"
    $missingQuest = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$missingQuestId" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Missing quest detail" -Actual $missingQuest.Status -Expected 404 -Body $missingQuest.Body
    Write-Pass "Missing quest returns 404"

    $missingRequirementId = [guid]::NewGuid().ToString().ToUpper()
    Write-Step "NEGATIVE: GET missing requirement contributions (expect 200 empty array)"
    $missingRequirement = Invoke-CurlJson -Method "GET" -Url "$base/api/requirements/$missingRequirementId/contributions" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Missing requirement contributions" -Actual $missingRequirement.Status -Expected 200 -Body $missingRequirement.Body
    $missingRequirementJson = Parse-JsonOrFail -Label "Missing requirement contributions" -Body $missingRequirement.Body
    $missingRequirementArray = Ensure-ArrayOrFail -Label "Missing requirement contributions" -Value $missingRequirementJson
    if (@($missingRequirementArray).Count -ne 0) {
        Fail "Missing requirement contributions expected empty array. Body: $($missingRequirement.Body)"
    }
    Write-Pass "Missing requirement contributions returns empty array"

    $memberFromEnv = Get-DotEnvValue -Path $envPath -Key "SMOKE_MEMBER_USERNAME"
    $memberPassFromEnv = Get-DotEnvValue -Path $envPath -Key "SMOKE_MEMBER_PASSWORD"
    if ([string]::IsNullOrWhiteSpace($MemberUsername) -and -not [string]::IsNullOrWhiteSpace($memberFromEnv)) {
        $MemberUsername = $memberFromEnv
    }
    if ([string]::IsNullOrWhiteSpace($MemberPassword) -and -not [string]::IsNullOrWhiteSpace($memberPassFromEnv)) {
        $MemberPassword = $memberPassFromEnv
    }

    if (-not [string]::IsNullOrWhiteSpace($MemberUsername) -and -not [string]::IsNullOrWhiteSpace($MemberPassword)) {
        Write-Step "MEMBER FLOW: create pending quest, approval and contribution permission checks"
        $memberCookieFile = Join-Path $tmpDir "member-cookies.txt"
        $memberLoginBody = @{ username = $MemberUsername; password = $MemberPassword } | ConvertTo-Json -Compress
        $memberLogin = Invoke-CurlJson -Method "POST" -Url "$base/api/login" -Body $memberLoginBody -CookieOut $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member login" -Actual $memberLogin.Status -Expected 200 -Body $memberLogin.Body

        $memberMe = Invoke-CurlJson -Method "GET" -Url "$base/api/me" -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member me endpoint" -Actual $memberMe.Status -Expected 200 -Body $memberMe.Body
        $memberMeJson = Parse-JsonOrFail -Label "Member me endpoint" -Body $memberMe.Body
        if (-not $memberMeJson.userId) {
            Fail "Member me endpoint missing userId. Body: $($memberMe.Body)"
        }

        $memberQuestTitle = "Member Smoke Quest " + (Get-Date -Format "yyyyMMdd-HHmmss")
        $memberCreateQuestBody = @{ title = $memberQuestTitle; description = "member pending quest"; status = "OPEN" } | ConvertTo-Json -Compress
        $memberCreateQuest = Invoke-CurlJson -Method "POST" -Url "$base/api/quests" -Body $memberCreateQuestBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member create quest" -Actual $memberCreateQuest.Status -Expected 200 -Body $memberCreateQuest.Body
        $memberCreatedQuest = Parse-JsonOrFail -Label "Member create quest" -Body $memberCreateQuest.Body
        if (-not $memberCreatedQuest.id) {
            Fail "Member create quest returned no id. Body: $($memberCreateQuest.Body)"
        }
        if ($memberCreatedQuest.isApproved -ne $false) {
            Fail "Member quest expected isApproved=false before admin approval. Body: $($memberCreateQuest.Body)"
        }
        if ($memberCreatedQuest.createdByUserId -ne $memberMeJson.userId) {
            Fail "Member quest createdByUserId mismatch. Body: $($memberCreateQuest.Body)"
        }

        $memberOwnQuestGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($memberCreatedQuest.id)" -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member reads own pending quest" -Actual $memberOwnQuestGet.Status -Expected 200 -Body $memberOwnQuestGet.Body

        Write-Step "MEMBER FLOW: contribution permissions on admin-owned quest"
        $memberContribBody = @{ qty = 2; status = "CLAIMED"; note = "member initial" } | ConvertTo-Json -Compress
        $memberContribCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/requirements/$($createdReq.id)/contributions" -Body $memberContribBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member create contribution on admin quest" -Actual $memberContribCreate.Status -Expected 200 -Body $memberContribCreate.Body
        $memberContribCreateJson = Parse-JsonOrFail -Label "Member create contribution on admin quest" -Body $memberContribCreate.Body
        if (-not $memberContribCreateJson.id) {
            Fail "Member contribution create returned no id. Body: $($memberContribCreate.Body)"
        }

        $memberContribUpdateBody = @{ qty = 4; note = "member updated" } | ConvertTo-Json -Compress
        $memberContribUpdate = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberContribCreateJson.id)" -Body $memberContribUpdateBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member edit own open contribution" -Actual $memberContribUpdate.Status -Expected 200 -Body $memberContribUpdate.Body
        $memberContribUpdateJson = Parse-JsonOrFail -Label "Member edit own open contribution" -Body $memberContribUpdate.Body
        if ($memberContribUpdateJson.qty -ne 4 -or $memberContribUpdateJson.note -ne "member updated") {
            Fail "Member contribution edit did not persist qty/note. Body: $($memberContribUpdate.Body)"
        }

        $memberContribCollectBody = @{ status = "COLLECTED" } | ConvertTo-Json -Compress
        $memberContribCollect = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberContribCreateJson.id)/status" -Body $memberContribCollectBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member sets own contribution COLLECTED" -Actual $memberContribCollect.Status -Expected 200 -Body $memberContribCollect.Body

        $memberContribDeliveredBody = @{ status = "DELIVERED" } | ConvertTo-Json -Compress
        $memberContribDelivered = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberContribCreateJson.id)/status" -Body $memberContribDeliveredBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member cannot set DELIVERED on admin quest" -Actual $memberContribDelivered.Status -Expected 403 -Body $memberContribDelivered.Body

        $adminDeliverMemberContrib = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberContribCreateJson.id)/status" -Body $memberContribDeliveredBody -CookieIn $cookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Admin sets DELIVERED on member contribution" -Actual $adminDeliverMemberContrib.Status -Expected 200 -Body $adminDeliverMemberContrib.Body

        $memberContribEditAfterDeliveredBody = @{ qty = 5; note = "should fail delivered" } | ConvertTo-Json -Compress
        $memberContribEditAfterDelivered = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberContribCreateJson.id)" -Body $memberContribEditAfterDeliveredBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member cannot edit delivered contribution" -Actual $memberContribEditAfterDelivered.Status -Expected 403 -Body $memberContribEditAfterDelivered.Body

        Write-Step "MEMBER FLOW: quest creator may set DELIVERED"
        $memberReqBody = @{ itemName = "Member Delivery Item"; qtyNeeded = 5; unit = "pcs" } | ConvertTo-Json -Compress
        $memberReqCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/quests/$($memberCreatedQuest.id)/requirements" -Body $memberReqBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member creates requirement on own pending quest" -Actual $memberReqCreate.Status -Expected 200 -Body $memberReqCreate.Body
        $memberReqCreateJson = Parse-JsonOrFail -Label "Member creates requirement on own pending quest" -Body $memberReqCreate.Body

        $memberOwnContribBody = @{ qty = 2; status = "CLAIMED"; note = "owner-delivery-test" } | ConvertTo-Json -Compress
        $memberOwnContribCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/requirements/$($memberReqCreateJson.id)/contributions" -Body $memberOwnContribBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member creates own quest contribution" -Actual $memberOwnContribCreate.Status -Expected 200 -Body $memberOwnContribCreate.Body
        $memberOwnContribCreateJson = Parse-JsonOrFail -Label "Member creates own quest contribution" -Body $memberOwnContribCreate.Body

        $memberOwnDeliveredBody = @{ status = "DELIVERED" } | ConvertTo-Json -Compress
        $memberOwnDelivered = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberOwnContribCreateJson.id)/status" -Body $memberOwnDeliveredBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Quest creator sets DELIVERED" -Actual $memberOwnDelivered.Status -Expected 200 -Body $memberOwnDelivered.Body

        $memberOwnEditAfterDeliveredBody = @{ qty = 3; note = "delivered-lock" } | ConvertTo-Json -Compress
        $memberOwnEditAfterDelivered = Invoke-CurlJson -Method "PATCH" -Url "$base/api/contributions/$($memberOwnContribCreateJson.id)" -Body $memberOwnEditAfterDeliveredBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Quest creator cannot edit delivered contribution" -Actual $memberOwnEditAfterDelivered.Status -Expected 403 -Body $memberOwnEditAfterDelivered.Body

        $memberPatchQuestBody = @{ status = "ARCHIVED" } | ConvertTo-Json -Compress
        $memberPatchQuest = Invoke-CurlJson -Method "PATCH" -Url "$base/api/quests/$($created.id)/status" -Body $memberPatchQuestBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member patch approved quest status" -Actual $memberPatchQuest.Status -Expected 403 -Body $memberPatchQuest.Body

        $memberApproveOwnQuest = Invoke-CurlJson -Method "POST" -Url "$base/api/quests/$($memberCreatedQuest.id)/approve" -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member approve quest forbidden" -Actual $memberApproveOwnQuest.Status -Expected 403 -Body $memberApproveOwnQuest.Body

        $adminApproveMemberQuest = Invoke-CurlJson -Method "POST" -Url "$base/api/quests/$($memberCreatedQuest.id)/approve" -CookieIn $cookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Admin approve member quest" -Actual $adminApproveMemberQuest.Status -Expected 200 -Body $adminApproveMemberQuest.Body
        $adminApproveMemberQuestJson = Parse-JsonOrFail -Label "Admin approve member quest" -Body $adminApproveMemberQuest.Body
        if ($adminApproveMemberQuestJson.isApproved -ne $true) {
            Fail "Admin approve response expected isApproved=true. Body: $($adminApproveMemberQuest.Body)"
        }

        $memberApprovedQuestGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$($memberCreatedQuest.id)" -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member reads approved quest" -Actual $memberApprovedQuestGet.Status -Expected 200 -Body $memberApprovedQuestGet.Body
        $memberApprovedQuestJson = Parse-JsonOrFail -Label "Member reads approved quest" -Body $memberApprovedQuestGet.Body
        if ($memberApprovedQuestJson.isApproved -ne $true) {
            Fail "Approved quest expected isApproved=true. Body: $($memberApprovedQuestGet.Body)"
        }

        $memberPatchOwnApprovedBody = @{ status = "DONE" } | ConvertTo-Json -Compress
        $memberPatchOwnApproved = Invoke-CurlJson -Method "PATCH" -Url "$base/api/quests/$($memberCreatedQuest.id)/status" -Body $memberPatchOwnApprovedBody -CookieIn $memberCookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Member patch own approved quest forbidden" -Actual $memberPatchOwnApproved.Status -Expected 403 -Body $memberPatchOwnApproved.Body

        Write-Pass "Member approval and contribution permission checks passed"
    } else {
        Write-Step "MEMBER FLOW skipped (SMOKE_MEMBER_USERNAME/SMOKE_MEMBER_PASSWORD not set)"
    }

    Write-Step "ADMIN DATA TRANSFER: GET $base/api/admin/data/export"
    $adminExport = Invoke-CurlJson -Method "GET" -Url "$base/api/admin/data/export" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin data export" -Actual $adminExport.Status -Expected 200 -Body $adminExport.Body
    $adminExportJson = Parse-JsonOrFail -Label "Admin data export" -Body $adminExport.Body
    if ($null -eq $adminExportJson.version -or $null -eq $adminExportJson.generatedAt) {
        Fail "Admin data export missing version/generatedAt. Body: $($adminExport.Body)"
    }
    if ($null -eq $adminExportJson.quests) {
        Fail "Admin data export missing quests array. Body: $($adminExport.Body)"
    }
    Write-Pass "Admin data export OK"

    Write-Step "ADMIN DATA TRANSFER: GET $base/api/admin/data/export/manifest"
    $adminExportManifest = Invoke-CurlJson -Method "GET" -Url "$base/api/admin/data/export/manifest" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin data export manifest" -Actual $adminExportManifest.Status -Expected 200 -Body $adminExportManifest.Body
    $adminExportManifestJson = Parse-JsonOrFail -Label "Admin data export manifest" -Body $adminExportManifest.Body
    if ($null -eq $adminExportManifestJson.counts -or $null -eq $adminExportManifestJson.counts.quests) {
        Fail "Admin data export manifest missing counts. Body: $($adminExportManifest.Body)"
    }
    Write-Pass "Admin data export manifest OK"

    Write-Step "ADMIN DATA TRANSFER: GET $base/api/admin/data/export/quests?limit=1&offset=0"
    $adminExportQuestChunk = Invoke-CurlJson -Method "GET" -Url "$base/api/admin/data/export/quests?limit=1&offset=0" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin data export quests chunk" -Actual $adminExportQuestChunk.Status -Expected 200 -Body $adminExportQuestChunk.Body
    $adminExportQuestChunkJson = Parse-JsonOrFail -Label "Admin data export quests chunk" -Body $adminExportQuestChunk.Body
    $adminExportQuestChunkArray = Ensure-ArrayOrFail -Label "Admin data export quests chunk" -Value $adminExportQuestChunkJson.quests
    if (@($adminExportQuestChunkArray).Count -gt 1) {
        Fail "Admin data export quests chunk expected max 1 quest for limit=1. Body: $($adminExportQuestChunk.Body)"
    }
    Write-Pass "Admin data export quests chunk OK"

    Write-Step "ADMIN DATA TRANSFER: iterate quest chunks (split export validation)"
    $manifestQuestCount = [int]$adminExportManifestJson.counts.quests
    $splitChunkSize = 50
    $splitOffset = 0
    $aggregatedQuestCount = 0
    $chunkCalls = 0
    while ($true) {
        $chunkResponse = Invoke-CurlJson -Method "GET" -Url "$base/api/admin/data/export/quests?limit=$splitChunkSize&offset=$splitOffset" -CookieIn $cookieFile -TmpDir $tmpDir
        Assert-HttpStatus -Label "Admin data export quest chunk page" -Actual $chunkResponse.Status -Expected 200 -Body $chunkResponse.Body
        $chunkJson = Parse-JsonOrFail -Label "Admin data export quest chunk page" -Body $chunkResponse.Body
        $chunkArray = Ensure-ArrayOrFail -Label "Admin data export quest chunk page" -Value $chunkJson.quests
        $chunkCount = @($chunkArray).Count
        $aggregatedQuestCount += $chunkCount
        $chunkCalls += 1
        if ($chunkCount -lt $splitChunkSize) {
            break
        }
        $splitOffset += $splitChunkSize
        if ($chunkCalls -gt 1000) {
            Fail "Admin data export split validation exceeded safety limit."
        }
    }
    if ($aggregatedQuestCount -ne $manifestQuestCount) {
        Fail "Admin data export split validation mismatch. Aggregated=$aggregatedQuestCount Manifest=$manifestQuestCount"
    }
    if ($manifestQuestCount -gt $splitChunkSize -and $chunkCalls -lt 2) {
        Fail "Expected multiple quest chunks for split validation, got only one."
    }
    Write-Pass "Admin data export split validation OK (chunks=$chunkCalls, total=$aggregatedQuestCount)"

    Write-Step "ADMIN DATA TRANSFER: POST $base/api/admin/data/import (inject one new quest)"
    $importQuestId = [guid]::NewGuid().ToString().ToUpper()
    $importQuestTitle = "Import Smoke Quest " + (Get-Date -Format "yyyyMMdd-HHmmss")
    $importQuestCreatedAt = (Get-Date).ToUniversalTime().ToString("o")
    $importQuest = [pscustomobject]@{
        id = $importQuestId
        title = $importQuestTitle
        description = "imported by smoke test"
        status = "OPEN"
        terminalSinceAt = $null
        deletedAt = $null
        createdAt = $importQuestCreatedAt
        createdByUserId = $meJson.userId
        isApproved = $true
        approvedAt = $importQuestCreatedAt
        approvedByUserId = $meJson.userId
    }
    $importPayloadObject = [pscustomobject]@{
        version = 1
        generatedAt = $importQuestCreatedAt
        users = @()
        quests = @($importQuest)
        requirements = @()
        contributions = @()
        passwordResetRequests = @()
        passwordResetTokens = @()
        apiTokens = @()
        auditEvents = @()
    }
    $importPayload = $importPayloadObject | ConvertTo-Json -Depth 30 -Compress

    $adminImport = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/data/import" -Body $importPayload -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin data import (first run)" -Actual $adminImport.Status -Expected 200 -Body $adminImport.Body
    $adminImportJson = Parse-JsonOrFail -Label "Admin data import (first run)" -Body $adminImport.Body
    if ($adminImportJson.questsInserted -ne 1) {
        Fail "Admin data import first run expected questsInserted=1. Body: $($adminImport.Body)"
    }
    Write-Pass "Admin data import first run OK (questsInserted=1)"

    Write-Step "ADMIN DATA TRANSFER: verify imported quest exists"
    $importedQuestGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$importQuestId" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Imported quest detail" -Actual $importedQuestGet.Status -Expected 200 -Body $importedQuestGet.Body
    $importedQuestGetJson = Parse-JsonOrFail -Label "Imported quest detail" -Body $importedQuestGet.Body
    if ($importedQuestGetJson.id -ne $importQuestId) {
        Fail "Imported quest id mismatch. Body: $($importedQuestGet.Body)"
    }
    Write-Pass "Imported quest verification OK"

    Write-Step "ADMIN DATA TRANSFER: POST $base/api/admin/data/import (dedupe second run)"
    $adminImportSecond = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/data/import" -Body $importPayload -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin data import (second run)" -Actual $adminImportSecond.Status -Expected 200 -Body $adminImportSecond.Body
    $adminImportSecondJson = Parse-JsonOrFail -Label "Admin data import (second run)" -Body $adminImportSecond.Body
    if ($adminImportSecondJson.questsInserted -ne 0) {
        Fail "Admin data import second run expected questsInserted=0. Body: $($adminImportSecond.Body)"
    }
    if ($adminImportSecondJson.questsSkipped -lt 1) {
        Fail "Admin data import second run expected questsSkipped>=1. Body: $($adminImportSecond.Body)"
    }
    Write-Pass "Admin data import dedupe OK"

    Write-Step "ADMIN DATA TRANSFER: split import (simulated multi-file payloads)"
    $splitQuestCreatedAt = (Get-Date).ToUniversalTime().ToString("o")
    $splitQuestAId = [guid]::NewGuid().ToString().ToUpper()
    $splitQuestBId = [guid]::NewGuid().ToString().ToUpper()
    $splitQuestA = [pscustomobject]@{
        id = $splitQuestAId
        title = "Split Import Quest A " + (Get-Date -Format "yyyyMMdd-HHmmss")
        description = "split-import-a"
        status = "OPEN"
        terminalSinceAt = $null
        deletedAt = $null
        createdAt = $splitQuestCreatedAt
        createdByUserId = $meJson.userId
        isApproved = $true
        approvedAt = $splitQuestCreatedAt
        approvedByUserId = $meJson.userId
    }
    $splitQuestB = [pscustomobject]@{
        id = $splitQuestBId
        title = "Split Import Quest B " + (Get-Date -Format "yyyyMMdd-HHmmss")
        description = "split-import-b"
        status = "OPEN"
        terminalSinceAt = $null
        deletedAt = $null
        createdAt = $splitQuestCreatedAt
        createdByUserId = $meJson.userId
        isApproved = $true
        approvedAt = $splitQuestCreatedAt
        approvedByUserId = $meJson.userId
    }

    $splitPayloadA = [pscustomobject]@{
        version = 1
        generatedAt = $splitQuestCreatedAt
        users = @()
        quests = @($splitQuestA)
        requirements = @()
        contributions = @()
        passwordResetRequests = @()
        passwordResetTokens = @()
        apiTokens = @()
        auditEvents = @()
    } | ConvertTo-Json -Depth 30 -Compress
    $splitPayloadB = [pscustomobject]@{
        version = 1
        generatedAt = $splitQuestCreatedAt
        users = @()
        quests = @($splitQuestB)
        requirements = @()
        contributions = @()
        passwordResetRequests = @()
        passwordResetTokens = @()
        apiTokens = @()
        auditEvents = @()
    } | ConvertTo-Json -Depth 30 -Compress

    $splitImportA = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/data/import" -Body $splitPayloadA -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin split import A" -Actual $splitImportA.Status -Expected 200 -Body $splitImportA.Body
    $splitImportAJson = Parse-JsonOrFail -Label "Admin split import A" -Body $splitImportA.Body
    if ($splitImportAJson.questsInserted -ne 1) {
        Fail "Admin split import A expected questsInserted=1. Body: $($splitImportA.Body)"
    }

    $splitImportB = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/data/import" -Body $splitPayloadB -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin split import B" -Actual $splitImportB.Status -Expected 200 -Body $splitImportB.Body
    $splitImportBJson = Parse-JsonOrFail -Label "Admin split import B" -Body $splitImportB.Body
    if ($splitImportBJson.questsInserted -ne 1) {
        Fail "Admin split import B expected questsInserted=1. Body: $($splitImportB.Body)"
    }

    $splitQuestAGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$splitQuestAId" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin split import quest A exists" -Actual $splitQuestAGet.Status -Expected 200 -Body $splitQuestAGet.Body
    $splitQuestBGet = Invoke-CurlJson -Method "GET" -Url "$base/api/quests/$splitQuestBId" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin split import quest B exists" -Actual $splitQuestBGet.Status -Expected 200 -Body $splitQuestBGet.Body
    Write-Pass "Admin split import multi-payload validation OK"

    Write-Step "INVITE FLOW: admin creates invite"
    $inviteCreateBody = @{ role = "member"; expiresInHours = 24 } | ConvertTo-Json -Compress
    $inviteCreate = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/invites" -Body $inviteCreateBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Invite create" -Actual $inviteCreate.Status -Expected 200 -Body $inviteCreate.Body
    $inviteCreateJson = Parse-JsonOrFail -Label "Invite create" -Body $inviteCreate.Body
    if (-not $inviteCreateJson.token -or -not $inviteCreateJson.invite.id) {
        Fail "Invite create response missing token/invite.id. Body: $($inviteCreate.Body)"
    }
    Write-Pass "Invite create OK"

    Write-Step "INVITE FLOW: register user by invite token"
    $inviteUserName = "InviteUser" + (Get-Date -Format "HHmmss")
    $inviteUserPassword = "InviteUser!123"
    $registerByInviteBody = @{
        token = $inviteCreateJson.token
        username = $inviteUserName
        password = $inviteUserPassword
    } | ConvertTo-Json -Compress
    $registerByInvite = Invoke-CurlJson -Method "POST" -Url "$base/api/register-by-invite" -Body $registerByInviteBody -TmpDir $tmpDir
    Assert-HttpStatus -Label "Register by invite" -Actual $registerByInvite.Status -Expected 200 -Body $registerByInvite.Body
    $registerByInviteJson = Parse-JsonOrFail -Label "Register by invite" -Body $registerByInvite.Body
    if ($registerByInviteJson.username -ne $inviteUserName) {
        Fail "Register by invite username mismatch. Body: $($registerByInvite.Body)"
    }
    Write-Pass "Register by invite OK"

    Write-Step "INVITE FLOW: login with invited user"
    $inviteLoginBody = @{ username = $inviteUserName; password = $inviteUserPassword } | ConvertTo-Json -Compress
    $inviteLogin = Invoke-CurlJson -Method "POST" -Url "$base/api/login" -Body $inviteLoginBody -TmpDir $tmpDir
    Assert-HttpStatus -Label "Login with invited user" -Actual $inviteLogin.Status -Expected 200 -Body $inviteLogin.Body
    Write-Pass "Invited user login OK"

    Write-Step "USER ROLE FLOW: list admin users"
    $adminUsers = Invoke-CurlJson -Method "GET" -Url "$base/api/admin/users" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Admin users list" -Actual $adminUsers.Status -Expected 200 -Body $adminUsers.Body
    $adminUsersJson = Parse-JsonOrFail -Label "Admin users list" -Body $adminUsers.Body
    $adminUsersArray = Ensure-ArrayOrFail -Label "Admin users list" -Value $adminUsersJson
    $invitedUserFromList = $adminUsersArray | Where-Object { $_.username -eq $inviteUserName } | Select-Object -First 1
    if ($null -eq $invitedUserFromList) {
        Fail "Invited user not found in admin users list."
    }

    Write-Step "USER ROLE FLOW: promote invited user to admin"
    $promoteBody = @{ role = "admin" } | ConvertTo-Json -Compress
    $promoteRes = Invoke-CurlJson -Method "PATCH" -Url "$base/api/admin/users/$($invitedUserFromList.id)/role" -Body $promoteBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Promote user role" -Actual $promoteRes.Status -Expected 200 -Body $promoteRes.Body
    $promoteJson = Parse-JsonOrFail -Label "Promote user role" -Body $promoteRes.Body
    if ($promoteJson.role -ne "admin") {
        Fail "Promote user role expected admin. Body: $($promoteRes.Body)"
    }

    Write-Step "USER ROLE FLOW: demote invited user back to member"
    $demoteBody = @{ role = "member" } | ConvertTo-Json -Compress
    $demoteRes = Invoke-CurlJson -Method "PATCH" -Url "$base/api/admin/users/$($invitedUserFromList.id)/role" -Body $demoteBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Demote user role" -Actual $demoteRes.Status -Expected 200 -Body $demoteRes.Body
    $demoteJson = Parse-JsonOrFail -Label "Demote user role" -Body $demoteRes.Body
    if ($demoteJson.role -ne "member") {
        Fail "Demote user role expected member. Body: $($demoteRes.Body)"
    }
    Write-Pass "User role promote/demote OK"

    Write-Step "POST $base/api/admin/retention/quests/cleanup (dry run)"
    $cleanupBody = @{ dryRun = $true; olderThanDays = 365 } | ConvertTo-Json -Compress
    $cleanup = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/retention/quests/cleanup" -Body $cleanupBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Retention cleanup dry run" -Actual $cleanup.Status -Expected 200 -Body $cleanup.Body
    $cleanupJson = Parse-JsonOrFail -Label "Retention cleanup dry run" -Body $cleanup.Body
    if ($null -eq $cleanupJson.candidateCount -or $null -eq $cleanupJson.deletedCount) {
        Fail "Retention cleanup response missing counts. Body: $($cleanup.Body)"
    }
    if ($cleanupJson.deletedCount -ne 0) {
        Fail "Retention dry run must not delete records. Body: $($cleanup.Body)"
    }
    Write-Pass "Retention cleanup dry run OK"

    Write-Step "POST $base/api/admin/retention/quests/cleanup (execute)"
    $cleanupExecBody = @{ dryRun = $false; olderThanDays = 365 } | ConvertTo-Json -Compress
    $cleanupExec = Invoke-CurlJson -Method "POST" -Url "$base/api/admin/retention/quests/cleanup" -Body $cleanupExecBody -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Retention cleanup execute" -Actual $cleanupExec.Status -Expected 200 -Body $cleanupExec.Body
    $cleanupExecJson = Parse-JsonOrFail -Label "Retention cleanup execute" -Body $cleanupExec.Body
    if ($null -eq $cleanupExecJson.candidateCount -or $null -eq $cleanupExecJson.deletedCount) {
        Fail "Retention cleanup execute response missing counts. Body: $($cleanupExec.Body)"
    }
    if ($cleanupExecJson.deletedCount -gt $cleanupExecJson.candidateCount) {
        Fail "Retention cleanup execute deletedCount exceeds candidateCount. Body: $($cleanupExec.Body)"
    }
    Write-Pass "Retention cleanup execute OK"

    Write-Step "POST $base/api/logout"
    $logout = Invoke-CurlJson -Method "POST" -Url "$base/api/logout" -CookieIn $cookieFile -CookieOut $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Logout endpoint" -Actual $logout.Status -Expected 200 -Body $logout.Body
    Write-Pass "Logout OK"

    Write-Step "GET $base/api/quests after logout (expect 401)"
    $afterLogout = Invoke-CurlJson -Method "GET" -Url "$base/api/quests" -CookieIn $cookieFile -TmpDir $tmpDir
    Assert-HttpStatus -Label "Quest list after logout" -Actual $afterLogout.Status -Expected 401 -Body $afterLogout.Body
    Write-Pass "Quest list after logout returns 401"

    Write-Host ""
    Write-Host "SMOKE TEST PASSED" -ForegroundColor Green
    exit 0
}
finally {
    if (Test-Path $tmpDir) {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
