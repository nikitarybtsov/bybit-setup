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

# В 32-разрядном PowerShell на 64-разрядной Windows система подменяет пути:
# System32 превращается в SysWOW64, Program Files — в Program Files (x86).
# Из-за этого не находятся ssh.exe и Chrome, а установка компонентов Windows
# работает через раз. Уходим в 64-разрядный интерпретатор, пока ничего не
# натворили. SysNative виден только 32-разрядным процессам — это и есть выход.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $native = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $native)) {
        Die "Запущен 32-разрядный PowerShell. Закрой это окно и открой «Терминал (администратор)» или «Windows PowerShell (администратор)» — БЕЗ пометки (x86)."
    }
    $selfUrl = if ($env:BYBIT_INSTALLER_URL) { $env:BYBIT_INSTALLER_URL }
               else { 'https://raw.githubusercontent.com/nikitarybtsov/bybit-setup/main/install.ps1' }
    Warn "открыт 32-разрядный PowerShell (x86) — перезапускаю в 64-разрядном"
    & $native -NoProfile -ExecutionPolicy Bypass -Command "irm '$selfUrl' | iex"
    exit $LASTEXITCODE
}

# --- 0. Проверки ----------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "Нужны права администратора. Закрой это окно, нажми правой кнопкой по «Пуск» -> «Терминал (администратор)» и вставь команду заново."
}

$cfgName = 'EMPLOYEE_BOT_CONFIG_EDIT_ME.txt'

# Файл настроек ищем до всего остального: в нём же лежит и токен доступа,
# поэтому сотруднику не нужно копировать его руками.
function Find-ConfigFile ($installDir) {
    $places = @(
        (Join-Path $installDir $cfgName),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) $cfgName),
        (Join-Path $env:USERPROFILE "Downloads\$cfgName"),
        (Join-Path $env:USERPROFILE "Documents\$cfgName"),
        (Join-Path $env:USERPROFILE "OneDrive\Desktop\$cfgName"),
        (Join-Path $env:USERPROFILE "OneDrive\Рабочий стол\$cfgName")
    )
    foreach ($p in $places) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Read-ConfigValue ($path, $name) {
    foreach ($line in (Get-Content $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($t.Substring(0, $i).Trim() -eq $name) { return $t.Substring($i + 1).Trim() }
    }
    return $null
}
$repoUrl    = 'https://github.com/nikitarybtsov/bybit_auto_bot2.0.git'
$branch     = if ($env:BYBIT_BRANCH) { $env:BYBIT_BRANCH } else { 'master' }
$installDir = if ($env:BYBIT_DIR)    { $env:BYBIT_DIR }    else { 'C:\BybitBot' }

if ($installDir -match 'OneDrive|Dropbox|Google Drive|Яндекс') {
    Die "Папка установки не должна лежать в облачной синхронизации ($installDir). Сообщи руководителю."
}

# Токен: сначала из файла настроек, потом — из переменной окружения, если её
# задали вручную. Ручное копирование токена в команду больше не требуется.
$configPath = Find-ConfigFile $installDir
$ghToken = ($env:BYBIT_TOKEN + '').Trim()
if (-not $ghToken -and $configPath) {
    $fromConfig = Read-ConfigValue $configPath 'BYBIT_TOKEN'
    if ($fromConfig) { $ghToken = $fromConfig.Trim() }
}
if (-not $ghToken) {
    Die @"
Не найден файл настроек $cfgName.

Распакуй архив, который прислал руководитель, и положи файл
    $cfgName
на рабочий стол. Затем запусти команду ещё раз.

Искал здесь:
  рабочий стол, Загрузки, Документы, $installDir
"@
}
# Токен из файла испортиться не может, а вот вставленный руками — легко:
# подчёркивания в нём мессенджеры принимают за разметку курсива.
if ($ghToken -notmatch '^github_pat_[A-Za-z0-9_]+$' -or $ghToken.Length -lt 80) {
    Die @"
Токен доступа повреждён: длина $($ghToken.Length), ожидается 93.

Если ты вставлял токен в команду руками — не надо: он берётся из файла
настроек. Убери из команды часть с BYBIT_TOKEN и запусти её заново.
"@
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
# ProgramW6432 всегда указывает на настоящий "C:\Program Files", даже если нас
# всё-таки запустили 32-разрядными — тогда $env:ProgramFiles врёт.
$chromePaths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramW6432 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
) | Where-Object { $_ }
if ($chromePaths | Where-Object { $_ -and (Test-Path $_) }) { Ok "уже установлен" }
else {
    Winget-Install 'Google.Chrome' 'Google Chrome'
    if ($chromePaths | Where-Object { $_ -and (Test-Path $_) }) { Ok "установлен" }
    else { Warn "Chrome не поставился автоматически. Поставь вручную с google.com/chrome — без него бот не откроет торговый аккаунт." }
}

# --- 4. OpenSSH -----------------------------------------------------------

Step 4 "Проверяю OpenSSH (защищённый канал к рабочему прокси)"
# Клиент OpenSSH входит в Windows 10 1809+ и обычно уже стоит; в PATH он может
# отсутствовать, поэтому проверяем и штатное расположение.
$sshBuiltin = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
if ((Have 'ssh') -or (Test-Path $sshBuiltin)) { Ok "уже установлен" }
else {
    try {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Client*' -ErrorAction Stop | Select-Object -First 1
        if ($cap -and $cap.State -ne 'Installed') {
            Say "    ставлю компонент Windows OpenSSH Client..."
            Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        }
    } catch { Warn "не удалось поставить OpenSSH автоматически" }
    Update-PathFromRegistry
    if ((Have 'ssh') -or (Test-Path $sshBuiltin)) { Ok "установлен" }
    else { Die "OpenSSH Client не установился. Параметры Windows -> Приложения -> Дополнительные компоненты -> Добавить компонент -> OpenSSH Client, затем запусти команду заново." }
}
# Туннель к прокси запускает сам бот, поэтому ssh должен находиться по имени.
if (-not (Have 'ssh') -and (Test-Path $sshBuiltin)) {
    $sshDirPath = Split-Path $sshBuiltin -Parent
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $sshDirPath) {
        [Environment]::SetEnvironmentVariable('Path', (@($userPath, $sshDirPath) | Where-Object { $_ }) -join ';', 'User')
        Update-PathFromRegistry
        Ok "добавил OpenSSH в PATH"
    }
}

# --- 5. Скачиваю бота -----------------------------------------------------

# --- 5. Системные часы -----------------------------------------------------

Step 5 "Сверяю системные часы"

# Bybit отклоняет запрос, чья отметка времени опережает биржевую больше чем на
# секунду: ErrCode 10002 приходит на каждый вызов, а снаружи это выглядит как
# «бот не работает». На свежей Windows часы уходят регулярно, и заметить это
# без подсказки почти невозможно.
Invoke-Quiet { & sc.exe config w32time start= auto 2>$null | Out-Null }
Invoke-Quiet { & net start w32time 2>$null | Out-Null }
Invoke-Quiet { & w32tm /resync /force 2>$null | Out-Null }
if ($LASTEXITCODE -eq 0) {
    Ok "часы синхронизированы"
} else {
    # Не повод останавливать установку: расхождение может быть и нулевым.
    Warn "не удалось синхронизировать часы автоматически. Открой Параметры -> Время и язык -> Дата и время и нажми «Синхронизировать»"
}

Step 6 "Скачиваю программу"

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

# Установщик работает с правами администратора, а бот потом запускается под
# обычной учётной записью сотрудника. Если для UAC вводили чужой пароль
# администратора, папка достаётся тому пользователю, и бот падает на записи
# состояния — уже посреди живой сделки. Выдаём права тому, кто реально сидит
# за компьютером.
$interactive = ''
try { $interactive = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch {}
if (-not $interactive) { $interactive = "$env:USERDOMAIN\$env:USERNAME" }
Invoke-Quiet { & icacls $installDir /grant "${interactive}:(OI)(CI)M" /T /C 2>$null | Out-Null }
if ($LASTEXITCODE -eq 0) { Ok "права на папку выданы: $interactive" }
else { Warn "не удалось выдать права на папку пользователю $interactive — если бот пожалуется на запись, покажи это руководителю" }

# --- 6. Окружение Python --------------------------------------------------

Step 7 "Готовлю окружение Python (самый долгий шаг, 3-10 минут)"
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

Step 8 "Ставлю файл настроек на место"
$dstCfg = Join-Path $installDir $cfgName
$configReady = $false
# Файл уже найден в самом начале — оттуда же был взят токен.
if ($configPath -and (Test-Path $configPath)) {
    if ($configPath -ne $dstCfg) { Copy-Item $configPath $dstCfg -Force }
    Ok "настройки на месте ($configPath)"
    $configReady = $true
} else {
    $again = Find-ConfigFile $installDir
    if ($again) {
        if ($again -ne $dstCfg) { Copy-Item $again $dstCfg -Force }
        Ok "нашёл и установил: $again"
        $configReady = $true
    } else {
        Warn "файла настроек нет — положи его на рабочий стол и запусти команду ещё раз"
    }
}

# Правило «не торговать со своими аккаунтами» живёт в этом файле, а не в коде.
# В свежей копии его нет (data/ не хранится в репозитории), и без него бот
# способен зайти в объявление собственного аккаунта. Кладём заготовку — но
# только если файла ещё нет: он пополняется в работе, затирать его нельзя.
$blName = 'counterparty_blacklist.json'
$blDst = Join-Path $installDir "data\$blName"
if (Test-Path $blDst) {
    Ok "список своих аккаунтов уже есть, не трогаю"
} else {
    $blSrc = $null
    foreach ($d in @((Split-Path $configPath -Parent), [Environment]::GetFolderPath('Desktop'),
                     (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Documents'))) {
        if ($d -and (Test-Path (Join-Path $d $blName))) { $blSrc = Join-Path $d $blName; break }
    }
    if ($blSrc) {
        New-Item -ItemType Directory -Force -Path (Split-Path $blDst -Parent) | Out-Null
        Copy-Item $blSrc $blDst -Force
        Ok "список своих аккаунтов установлен"
    } else {
        Warn "нет $blName — бот не будет знать свои аккаунты, сообщи руководителю"
    }
}

# --- 8. SSH-ключ для прокси ----------------------------------------------

Step 9 "Готовлю ключ доступа к рабочему прокси"
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

Step 10 "Создаю ярлыки на рабочем столе"
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
