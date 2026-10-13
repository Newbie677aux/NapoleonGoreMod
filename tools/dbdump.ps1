param([string]$Pack, [string]$Entry, [int]$MaxTokens = 4000)
# Грубый разбор db-таблицы NTW без схемы: идёт по байтам и печатает строки UTF-16 (u16 длина + символы)
# и числа между ними. Нужен, чтобы увидеть, какие колонки и значения есть в строках таблицы.
. "$PSScriptRoot\packlib.ps1"
$b = Read-PackFile $Pack $Entry
$p = 0; $tokens = New-Object System.Collections.Generic.List[string]
while ($p -lt $b.Length -and $tokens.Count -lt $MaxTokens) {
    # строка: u16 длина + UTF-16; опциональная строка: байт-флаг (0/1) + строка
    $str = $null
    foreach ($skip in 0, 1) {
        $q = $p + $skip
        if ($skip -and $b[$p] -gt 1) { continue }
        if ($q + 2 -gt $b.Length) { continue }
        $len = [BitConverter]::ToUInt16($b, $q)
        if ($len -ge 2 -and $len -le 200 -and $q + 2 + 2 * $len -le $b.Length) {
            $s = [Text.Encoding]::Unicode.GetString($b, $q + 2, 2 * $len)
            if ($s -match '^[\x20-\x7E]+$') { $str = $s; $p = $q + 2 + 2 * $len; $tokens.Add($(if ($skip) { "?'$s'" } else { "'$s'" })); break }
        }
    }
    if ($str) { continue }
    if ($b[$p] -le 1 -and $p + 1 -lt $b.Length -and $b[$p + 1] -eq 0 -and $p + 2 -lt $b.Length -and $b[$p + 2] -eq 0) { }  # пусто: ниже как число
    elseif ($b[$p] -le 1) { $tokens.Add("f$($b[$p])"); $p++; continue }
    if ($p + 4 -le $b.Length) {
        $u = [BitConverter]::ToUInt32($b, $p); $f = [BitConverter]::ToSingle($b, $p)
        if ($u -lt 100000) { $tokens.Add("$u") }
        elseif ([math]::Abs($f) -gt 1e-4 -and [math]::Abs($f) -lt 1e6) { $tokens.Add(('{0:G5}f' -f $f)) }
        else { $tokens.Add(('0x{0:X8}' -f $u)) }
        $p += 4
    } else { $tokens.Add(('b{0:X2}' -f $b[$p])); $p++ }
}
"$Entry  ($($b.Length) байт)"
$tokens -join ' '
