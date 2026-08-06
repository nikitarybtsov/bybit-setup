# Bybit 2.0 Команда — установка рабочего места сотрудника одной командой.
#
# Ставит Python, Git, Google Chrome, OpenSSH, копию бота из GitHub,
# изолированное окружение Python, SSH-ключ для рабочего прокси и ярлыки запуска.
#
# Запуск (PowerShell ОТ ИМЕНИ АДМИНИСТРАТОРА):
#   $env:BYBIT_TOKEN='<токен>'; irm https://raw.githubusercontent.com/nikitarybtsov/bybit-setup/main/install.ps1 | iex
#
# Необязательные переменные:
#   $env:BYBIT_DIR    — куда ставить (по умолчанию C:\BybitBot)
#   $env:BYBIT_BRANCH — ветка (по умолчанию master)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Say  ($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Step ($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok   ($t) { Write-Host "    OK: $t" -ForegroundColor Green }
function Warn ($t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Die  ($t) {
    Write-Host "`nОШИБКА: $t" -ForegroundColor Red
    Write-Host "`nСделай скриншот ВСЕГО этого окна и отправь руководителю." -ForegroundColor Red
    Write-Host "Ничего не скачивай в интернете в качестве исправления." -ForegroundColor Red
    # Окно закрывается по exit, поэтому даём время снять скриншот.
    Read-Host "`nСними скриншот, потом нажми Enter" | Out-Null
    exit 1
}

Say "`n=== Установка рабочего места: Bybit 2.0 Команда ===`n" 'White'

# --- 0. Проверки ----------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "Нужны права администратора. Закрой это окно, нажми правой кнопкой по «Пуск» -> «Терминал (администратор)» и вставь команду заново."
}

$ghToken = $env:BYBIT_TOKEN
if (-not $ghToken) { Die "Не задан токен доступа. Скопируй команду руководителя ЦЕЛИКОМ (обе части, до и после точки с запятой)." }

$repoUrl    = 'https://github.com/nikitarybtsov/bybit_auto_bot2.0.git'
$branch     = if ($env:BYBIT_BRANCH) { $env:BYBIT_BRANCH } else { 'master' }
$installDir = if ($env:BYBIT_DIR)    { $env:BYBIT_DIR }    else { 'C:\BybitBot' }

if ($installDir -match 'OneDrive|Dropbox|Google Drive|Яндекс') {
    Die "Папка установки не должна лежать в облачной синхронизации ($installDir). Сообщи руководителю."
}

Say "Папка установки : $installDir"
Say "Ветка           : $branch"

function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Have ($name) {
    try { return [bool](Get-Command $name -ErrorAction Stop) } catch { return $false }
}

# PowerShell 5.1 заворачивает stderr перенаправленной нативной программы в
# объекты ошибок, и при $ErrorActionPreference='Stop' обычная неудачная проверка
# (например «py -3.13» на машине без 3.13) становится фатальной. Пробы окружения
# запускаем через этот помощник: их провал — нормальный ответ, а не сбой.
function Invoke-Quiet {
    param([scriptblock] $Script)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Script } catch { } finally { $ErrorActionPreference = $prev }
}

function Winget-Install ($id, $label) {
    if (-not (Have 'winget')) {
        Die "На этом компьютере нет winget (магазин приложений Windows), поэтому $label автоматически не ставится. Сообщи руководителю."
    }
    Say "    ставлю $label, это может занять несколько минут..."
    Invoke-Quiet {
        & winget install --id $id --silent --accept-source-agreements `
            --accept-package-agreements --disable-interactivity 2>&1 | Out-Null
    }
    Update-PathFromRegistry
}

# --- 1. Python ------------------------------------------------------------

Step 1 "Проверяю Python"

function Find-Python {
    $candidates = @()
    foreach ($root in @("$env:LOCALAPPDATA\Programs\Python", "$env:ProgramFiles", "${env:ProgramFiles(x86)}")) {
        if (Test-Path $root) {
            $candidates += Get-ChildItem $root -Filter 'Python3*' -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName 'python.exe' }
        }
    }
    if (Have 'py') {
        foreach ($v in @('3.13', '3.12', '3.11')) {
            # Отсутствие версии — обычный ответ launcher'а, не ошибка установки.
            $p = Invoke-Quiet { & py "-$v" -c "import sys; print(sys.executable)" 2>$null }
            if ($p) { $candidates = @($p) + $candidates }
        }
    }
    if (Have 'python') {
        $p = (Get-Command python -ErrorAction SilentlyContinue).Source
        if ($p -and $p -notmatch 'WindowsApps') { $candidates += $p }
    }
    foreach ($c in $candidates) {
        if (-not (Test-Path $c)) { continue }
        $v = Invoke-Quiet {
            & $c -c "import sys; print('%d.%d' % sys.version_info[:2]); print(sys.maxsize > 2**32)" 2>$null
        }
        if (-not $v -or $v.Count -lt 2) { continue }
        if ($v[1] -ne 'True') { continue }
        if ($v[0] -in @('3.11', '3.12', '3.13')) { return $c }
    }
    return $null
}

$python = Find-Python
if ($python) {
    Ok "уже установлен ($python)"
} else {
    Winget-Install 'Python.Python.3.12' 'Python 3.12'
    $python = Find-Python
    if (-not $python) { Die "Python не установился. Поставь вручную с python.org версию 3.12 (64-bit) с галочкой «Add Python to PATH» и запусти команду заново." }
    Ok "установлен ($python)"
}

# --- 2. Git ---------------------------------------------------------------

Step 2 "Проверяю Git"
if (Have 'git') { Ok "уже установлен" }
else {
    Winget-Install 'Git.Git' 'Git'
    if (-not (Have 'git')) { Die "Git не установился. Поставь вручную с git-scm.com и запусти команду заново." }
    Ok "установлен"
}

# --- 3. Google Chrome -----------------------------------------------------

Step 3 "Проверяю Google Chrome (в нём открывается торговый аккаунт)"
$chromePaths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
if ($chromePaths | Where-Object { $_ -and (Test-Path $_) }) { Ok "уже установлен" }
else {
    Winget-Install 'Google.Chrome' 'Google Chrome'
    if ($chromePaths | Where-Object { $_ -and (Test-Path $_) }) { Ok "установлен" }
    else { Warn "Chrome не поставился автоматически. Поставь вручную с google.com/chrome — без него бот не откроет торговый аккаунт." }
}

# --- 4. OpenSSH -----------------------------------------------------------

Step 4 "Проверяю OpenSSH (защищённый канал к рабочему прокси)"
if (Have 'ssh') { Ok "уже установлен" }
else {
    try {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Client*' -ErrorAction Stop | Select-Object -First 1
        if ($cap -and $cap.State -ne 'Installed') {
            Say "    ставлю компонент Windows OpenSSH Client..."
            Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        }
    } catch { Warn "не удалось поставить OpenSSH автоматически" }
    Update-PathFromRegistry
    if (Have 'ssh') { Ok "установлен" }
    else { Die "OpenSSH Client не установился. Параметры Windows -> Приложения -> Дополнительные компоненты -> Добавить компонент -> OpenSSH Client, затем запусти команду заново." }
}

# --- 5. Скачиваю бота -----------------------------------------------------

Step 5 "Скачиваю программу"

# Токен идёт прямо в адресе репозитория. Хранилище учётных данных не трогаем:
# в Git for Windows на системном уровне включён Git Credential Manager, его
# спрашивают первым, и он открыл бы сотруднику окно входа в GitHub. Заодно так
# работает и обновление кнопкой из Telegram — без окон и без чужого аккаунта.
$authUrl = $repoUrl -replace '^https://', "https://x-access-token:$ghToken@"
# Ни один helper не опрашивается, а git не ждёт ввода в консоли.
$gitAuth = @('-c', 'credential.helper=')
$env:GIT_TERMINAL_PROMPT = '0'

if (Test-Path (Join-Path $installDir '.git')) {
    Say "    папка уже существует, обновляю..."
    & git @gitAuth -C $installDir remote set-url origin $authUrl
    & git @gitAuth -C $installDir fetch origin $branch
    if ($LASTEXITCODE -ne 0) { Die "Не удалось скачать обновление с GitHub. Проверь интернет; если ошибка про доступ — сообщи руководителю, нужен новый токен." }
    $dirty = & git -C $installDir status --porcelain
    if ($dirty) { Warn "в папке есть изменённые файлы, обновление не применял" }
    else { & git -C $installDir reset --hard "origin/$branch" | Out-Null; Ok "обновлено до последней версии" }
} else {
    # Для C:\BybitBot родителем оказывается корень диска, а New-Item на "C:\"
    # падает с "путь имеет недопустимую форму". Создаём только то, чего нет.
    $parent = Split-Path $installDir -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    # Прерванный клон оставляет пустую папку, а git отказывается клонировать
    # в непустую. Пустую убираем молча, непустую не трогаем — это уже данные.
    if (Test-Path $installDir) {
        if (@(Get-ChildItem $installDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $installDir -Force -Recurse
        } else {
            Die "Папка $installDir уже есть и не пуста, но это не копия программы. Покажи её содержимое руководителю — удалять сам ничего не надо."
        }
    }
    & git @gitAuth clone --branch $branch $authUrl $installDir
    if ($LASTEXITCODE -ne 0) { Die "Не удалось скачать программу с GitHub. Проверь интернет; если ошибка про доступ (403/authentication) — сообщи руководителю, нужен новый токен." }
    Ok "скачано в $installDir"
}
Invoke-Quiet { & git config --global --add safe.directory ($installDir -replace '\\', '/') 2>$null | Out-Null }

# --- 6. Окружение Python --------------------------------------------------

Step 6 "Готовлю окружение Python (самый долгий шаг, 3-10 минут)"
$venvPython = Join-Path $installDir '.venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    & $python -m venv (Join-Path $installDir '.venv')
    if (-not (Test-Path $venvPython)) { Die "Не удалось создать окружение Python в $installDir\.venv" }
}
& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install -r (Join-Path $installDir 'requirements.txt')
if ($LASTEXITCODE -ne 0) { Die "Не удалось установить библиотеки Python. Проверь интернет и запусти команду ещё раз — повтор безопасен." }
Ok "окружение готово"

# --- 7. Персональный конфиг ----------------------------------------------

Step 7 "Ищу файл настроек от руководителя"
$cfgName = 'EMPLOYEE_BOT_CONFIG_EDIT_ME.txt'
$dstCfg = Join-Path $installDir $cfgName
$configReady = $false
if (Test-Path $dstCfg) {
    Ok "настройки уже на месте"
    $configReady = $true
} else {
    $searchIn = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents')
    )
    $found = $null
    foreach ($dir in $searchIn) {
        if (-not $dir -or -not (Test-Path $dir)) { continue }
        $hit = Get-ChildItem $dir -Filter $cfgName -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $found = $hit.FullName; break }
    }
    if ($found) {
        Copy-Item $found $dstCfg -Force
        Ok "нашёл и установил: $found"
        $configReady = $true
    } else {
        Warn "файла настроек пока нет — положишь его позже, см. инструкцию в конце"
    }
}

# --- 8. SSH-ключ для прокси ----------------------------------------------

Step 8 "Готовлю ключ доступа к рабочему прокси"
$sshDir = Join-Path $env:USERPROFILE '.ssh'
$keyPath = Join-Path $sshDir 'id_ed25519'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
if (Test-Path $keyPath) { Ok "ключ уже есть, оставляю прежний" }
else {
    & ssh-keygen -t ed25519 -f $keyPath -N '""' -q
    if (-not (Test-Path "$keyPath.pub")) { Die "Не удалось создать ключ доступа ($keyPath)." }
    Ok "ключ создан"
}
$desktop = [Environment]::GetFolderPath('Desktop')
$pubOut = Join-Path $desktop 'КЛЮЧ_ДЛЯ_ВЛАДЕЛЬЦА.txt'
Copy-Item "$keyPath.pub" $pubOut -Force
Ok "файл для руководителя: $pubOut"

# --- 9. Ярлыки ------------------------------------------------------------

Step 9 "Создаю ярлыки на рабочем столе"
$shell = New-Object -ComObject WScript.Shell
$links = @(
    @{ Name = '1 Проверка настроек.lnk';          Target = 'CHECK_EMPLOYEE_BOT_CONFIG.cmd';   Icon = 'shell32.dll,23' },
    @{ Name = '2 Вход в Bybit.lnk';               Target = 'INIT_EMPLOYEE_TAKER_SESSION.cmd'; Icon = 'shell32.dll,14' },
    @{ Name = '3 Публикация меню (один раз).lnk'; Target = 'PUBLISH_EMPLOYEE_BOT_MENU.cmd';   Icon = 'shell32.dll,177' },
    @{ Name = '4 Запуск бота.lnk';                Target = 'START_EMPLOYEE_BOT.cmd';          Icon = 'shell32.dll,137' }
)
foreach ($l in $links) {
    $target = Join-Path $installDir $l.Target
    if (-not (Test-Path $target)) { Warn "не найден $($l.Target)"; continue }
    $lnk = $shell.CreateShortcut((Join-Path $desktop $l.Name))
    $lnk.TargetPath = $target
    $lnk.WorkingDirectory = $installDir
    $lnk.IconLocation = $l.Icon
    $lnk.Save()
}
Ok "ярлыки готовы"

# --- Итог -----------------------------------------------------------------

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " Установка завершена." -ForegroundColor Green
Write-Host "=====================================================`n" -ForegroundColor Green

Write-Host "ЧТО ДЕЛАТЬ ДАЛЬШЕ:`n" -ForegroundColor White
$n = 1
if (-not $configReady) {
    Write-Host "  $n. Сохрани присланный руководителем файл" -ForegroundColor White
    Write-Host "     $cfgName" -ForegroundColor Yellow
    Write-Host "     в папку $installDir" -ForegroundColor White
    Write-Host "     (или просто на рабочий стол и запусти команду установки ещё раз)`n" -ForegroundColor Gray
    $n++
}
Write-Host "  $n. Отправь руководителю файл с рабочего стола:" -ForegroundColor White
Write-Host "     КЛЮЧ_ДЛЯ_ВЛАДЕЛЬЦА.txt" -ForegroundColor Yellow
Write-Host "     (это открытая часть ключа, её можно пересылать)`n" -ForegroundColor Gray
$n++
Write-Host "  $n. Дождись ответа «ключ добавлен».`n" -ForegroundColor White
$n++
Write-Host "  $n. Запусти ярлык «1 Проверка настроек» и пришли руководителю" -ForegroundColor White
Write-Host "     скриншот того, что покажет окно.`n" -ForegroundColor White

Write-Host "НИКОМУ не отправляй файл id_ed25519 (без .pub) из папки $sshDir" -ForegroundColor Red
Write-Host "Бота не запускай, пока руководитель не разрешит.`n" -ForegroundColor Red

Read-Host "Нажми Enter, чтобы закрыть окно" | Out-Null
