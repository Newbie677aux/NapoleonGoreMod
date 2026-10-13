param([string]$Pack, [string]$OutFile)
# Read-only PFH0 (Napoleon TW) index reader: header + file list with sizes.
$fs = [IO.File]::OpenRead($Pack)
$br = New-Object IO.BinaryReader($fs)
try {
  $magic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
  $type = $br.ReadUInt32(); $depCount = $br.ReadUInt32(); $depSize = $br.ReadUInt32()
  $fileCount = $br.ReadUInt32(); $idxSize = $br.ReadUInt32()
  $types = @{0='boot';1='release';2='patch';3='mod';4='movie'}
  $deps = [Text.Encoding]::ASCII.GetString($br.ReadBytes($depSize)).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)
  $idx = $br.ReadBytes($idxSize)
  $lines = New-Object Collections.Generic.List[string]
  $p = 0
  for ($i = 0; $i -lt $fileCount; $i++) {
    $size = [BitConverter]::ToUInt32($idx, $p); $p += 4
    $e = [Array]::IndexOf($idx, [byte]0, $p)
    $name = [Text.Encoding]::ASCII.GetString($idx, $p, $e - $p); $p = $e + 1
    $lines.Add("$size`t$name")
  }
  "{0}`t{1}`ttype={2}({3})`tfiles={4}`tdeps={5}" -f (Split-Path $Pack -Leaf), $magic, $type, $types[[int]$type], $fileCount, ($deps -join ',')
  if ($OutFile) { $lines | Set-Content -Encoding utf8 $OutFile }
} finally { $br.Close() }
