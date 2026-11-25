# Windows PowerShell 5.1 / PowerShell 7: test worker decoding without FFmpeg or Aseprite.
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\extension\RawEncoder.cs')
$work = Join-Path ([IO.Path]::GetTempPath()) ('aselaps-native-' + [Guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($work)
try {
    $pack = Join-Path $work 'frames.pack'
    $writer = [IO.BinaryWriter]::new([IO.File]::Create($pack))
    # Reference: 3 pixels, all RGBA 10,20,30,255 (negative run).
    $writer.Write([uint32]0); $writer.Write([uint32]6); $writer.Write([int16]-3)
    $writer.Write([byte[]](10,20,30,255))
    $offset = $writer.BaseStream.Position
    # Delta: replace center pixel with literal RGBA 40,50,60,255.
    $writer.Write([uint32]1); $writer.Write([uint32]6); $writer.Write([int16]1)
    $writer.Write([byte[]](40,50,60,255)); $writer.Close()
    # New reference in a recovery pack; resize from 3x1 to 2x1.
    $writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $work 'frames.000001.pack')))
    $writer.Write([uint32]0); $writer.Write([uint32]6); $writer.Write([int16]-2)
    $writer.Write([byte[]](70,80,90,255)); $writer.Close()
    $manifest = Join-Path $work 'frames.index'
    # Select out of order, repeat, crop and pad. Expected output is 3x1 per frame.
    @('3 1 3 4','0 0 14 3 1 1 1',"0 $offset 14 3 1 0 1",'1 0 14 2 1 1 3','2 0 0','1 -1 0','3 1 0','2 0 0') | Set-Content -LiteralPath $manifest -Encoding ASCII
    $out = New-Object IO.MemoryStream
    [AseLapsRawEncoder]::WriteNative($manifest, $work, $out, (Join-Path $work 'cancel'))
    $expected = [byte[]](10,20,30,255,40,50,60,255,10,20,30,255, 10,20,30,255,10,20,30,255,0,0,0,0, 0,0,0,0,70,80,90,255,70,80,90,255, 10,20,30,255,40,50,60,255,10,20,30,255)
    if ([Convert]::ToBase64String($out.ToArray()) -ne [Convert]::ToBase64String($expected)) { throw 'Worker RGBA mismatch' }
    $out.Dispose()
    Write-Host 'ASELAPS_NATIVE_WORKER_OK'
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
