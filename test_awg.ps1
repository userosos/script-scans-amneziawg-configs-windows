# 1. Поиск AmneziaWG на диске
$AwgPaths = @(
    "$env:ProgramFiles\AmneziaWG\amneziawg.exe",
    "C:\Program Files\AmneziaWG\amneziawg.exe",
    "$env:ProgramFiles\AmneziaVPN\amneziawg.exe",
    "C:\Program Files\AmneziaVPN\amneziawg.exe"
)

$AwgExe = $null
foreach ($path in $AwgPaths) {
    if (Test-Path $path) {
        $AwgExe = $path
        break
    }
}

if (-not $AwgExe) {
    Write-Host "`n[ОШИБКА] Клиент AmneziaWG не найден!" -ForegroundColor Red
    Write-Host "Убедитесь, что установлен именно AmneziaWG (папка C:\Program Files\AmneziaWG\).`n" -ForegroundColor Yellow
    return
}

Write-Host "`nИспользуется AmneziaWG: $AwgExe" -ForegroundColor Cyan

# 2. Определение текущего домашнего IP (для защиты от ложных OK)
Write-Host "Определяем ваш реальный IP... " -NoNewline
$realIp =$null
try {
    $realIp = (curl.exe -s --max-time 5 https://api.ipify.org).Trim()
    Write-Host "$realIp" -ForegroundColor Yellow
} catch {
    Write-Host "Ошибка (проверьте интернет)" -ForegroundColor Red
}

# 3. Подготовка папок и отчета
$working = ".\working"
$failed  = ".\failed"
$csv     = ".\results.csv"

New-Item -ItemType Directory -Force -Path $working,$failed | Out-Null
"config,status,external_ip" | Out-File -FilePath $csv -Encoding ascii

# 4. Поиск всех .conf (в текущей папке и подпапках, кроме уже отсортированных)
$confs = Get-ChildItem -Path "." -Recurse -Filter *.conf | Where-Object { 
    $_.Name -ne "awgtest.conf" -and $_.FullName -notmatch '\\(working|failed)\\' 
}

if ($confs.Count -eq 0) {
    Write-Host "[ОШИБКА] Файлы .conf не найдены!" -ForegroundColor Red
    return
}

Write-Host "Конфигураций для проверки: $($confs.Count)`n"

# Очистка службы AmneziaWG перед стартом (если осталась от предыдущих тестов)
& sc.exe stop 'AmneziaWGTunnel$awgtest' *>$null
& sc.exe delete 'AmneziaWGTunnel$awgtest' *>$null
Start-Sleep -Seconds 1

# 5. Цикл тестирования через AmneziaWG
foreach ($f in $confs) {
    Write-Host "Проверка $($f.Name)... " -NoNewline

    $tmp = Join-Path $env:TEMP "awgtest.conf"
    Copy-Item $f.FullName -Destination $tmp -Force

    # Запуск службы через AmneziaWG
    Start-Process -FilePath $AwgExe -ArgumentList "/installtunnelservice `"$tmp`"" -Wait -WindowStyle Hidden

    # Пауза на обфусцированное рукопожатие (Jc, S1, S2) и маршрутизацию
    Start-Sleep -Seconds 4

    # Проверка доступности сети
    $ip = $null
    try {
        $ip = (curl.exe -s --max-time 5 https://api.ipify.org).Trim()
    } catch {}

    # Принудительная остановка и удаление службы через консольную sc.exe (без GUI-окон)
    & sc.exe stop 'AmneziaWGTunnel$awgtest' *>$null
    & sc.exe delete 'AmneziaWGTunnel$awgtest' *>$null

    Start-Sleep -Seconds 1
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    # Валидация IP
    $ok = ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') -and ($ip -ne $realIp)

    if ($ok) {
        Write-Host "OK (IP: $ip)" -ForegroundColor Green
        Move-Item -Path $f.FullName -Destination $working -Force
        "$($f.Name),SUCCESS,$ip" | Out-File -FilePath $csv -Append -Encoding ascii
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        Move-Item -Path $f.FullName -Destination $failed -Force
        "$($f.Name),FAIL," | Out-File -FilePath $csv -Append -Encoding ascii
    }
}

Write-Host "`nТестирование завершено! Результаты сохранены в $csv" -ForegroundColor Cyan
