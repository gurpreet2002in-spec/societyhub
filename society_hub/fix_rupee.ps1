Get-ChildItem -Path "f:\society app\society_hub\lib" -Recurse -Filter *.dart | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    if ($content.Contains('\u20B9')) {
        if ($content.Contains('\\u20B9')) {
            $newContent = $content.Replace('\\u20B9', '\u20B9')
            [IO.File]::WriteAllText($_.FullName, $newContent)
            Write-Host "Fixed: $($_.FullName)"
        }
    }
}
