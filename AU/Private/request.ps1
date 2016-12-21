function request( [string]$Url, [int]$Timeout=$global:au_Timeout ) {
    if ([string]::IsNullOrWhiteSpace($url)) {throw 'The URL is empty'}
    $request = [System.Net.WebRequest]::Create($Url)
    if ($Timeout)  { $request.Timeout = $Timeout*1000 }

    $response = $request.GetResponse()
    $response.Close()
    $response
}
