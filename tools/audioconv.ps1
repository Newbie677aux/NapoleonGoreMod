param([string]$In, [string]$Out)
# Перекодирование аудио встроенными средствами Windows (Media Foundation), без сторонних программ.
# Формат результата по расширению $Out:
#   .wav — PCM 16-bit (из FLAC/OGG/MP3);
#   .mp3 — mono 44.1 kHz 160 kbps, как голосовые файлы игры (из WAV).
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$methods = [System.WindowsRuntimeSystemExtensions].GetMethods()
$asTaskOp = $methods | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asTaskProgress = $methods | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1' } | Select-Object -First 1
function Await($op, [type]$t) { $task = $asTaskOp.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(); $task.Result }
function AwaitAction($op) { $task = $asTaskProgress.MakeGenericMethod([double]).Invoke($null, @($op)); $task.Wait() }

[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]
[void][Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]

$In = (Resolve-Path -LiteralPath $In).Path
$OutDir = (Resolve-Path -LiteralPath (Split-Path $Out)).Path
$src = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($In)) ([Windows.Storage.StorageFile])
$dir = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($OutDir)) ([Windows.Storage.StorageFolder])
$dst = Await ($dir.CreateFileAsync((Split-Path $Out -Leaf), [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])

$quality = [Windows.Media.MediaProperties.AudioEncodingQuality]::High
switch ([IO.Path]::GetExtension($Out).ToLower()) {
    '.wav' { $profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateWav($quality) }
    '.mp3' {
        $profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp3($quality)
        $profile.Audio.ChannelCount = 1; $profile.Audio.SampleRate = 44100; $profile.Audio.Bitrate = 160000
    }
    default { throw "Неизвестный формат: $Out" }
}
$tc = New-Object Windows.Media.Transcoding.MediaTranscoder
$prep = Await ($tc.PrepareFileTranscodeAsync($src, $dst, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
if (-not $prep.CanTranscode) { throw "Не могу перекодировать $In : $($prep.FailureReason)" }
AwaitAction ($prep.TranscodeAsync())
"ok $Out"
