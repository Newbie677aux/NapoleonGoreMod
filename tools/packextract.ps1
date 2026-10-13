param([string]$Pack, [string]$Pattern, [string]$OutDir)
# Read-only PFH0 extractor: copies entries whose path matches $Pattern into $OutDir.
$fs = [IO.File]::OpenRead($Pack)
$br = New-Object IO.BinaryReader($fs)
try {
  $null = $br.ReadBytes(4); $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $depSize = $br.ReadUInt32()
  $fileCount = $br.ReadUInt32(); $idxSize = $br.ReadUInt32()
  $null = $br.ReadBytes($depSize); $idx = $br.ReadBytes($idxSize)
  $offset = [int64](24 + $depSize + $idxSize); $p = 0
  for ($i = 0; $i -lt $fileCount; $i++) {
    $size = [BitConverter]::ToUInt32($idx, $p); $p += 4
    $e = [Array]::IndexOf($idx, [byte]0, $p)
    $name = [Text.Encoding]::ASCII.GetString($idx, $p, $e - $p); $p = $e + 1
    if ($name -match $Pattern) {
      $fs.Position = $offset
      $out = Join-Path $OutDir ($name -replace '[\\/]', '__')
      [IO.File]::WriteAllBytes($out, $br.ReadBytes($size))
      "extracted $name ($size)"
    }
    $offset += $size
  }
} finally { $br.Close() }
