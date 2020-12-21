#! /bin/sh

docker rm -f edgewebapp 2>/dev/null
docker run \
        -d \
        --name edgewebapp \
        -p 5001:443 \
        -p 5000:80 \
        -e ASPNETCORE_HTTPS_PORT=443 \
        -e ASPNETCORE_URLS='https://+;http://+' \
        -e ASPNETCORE_Kestrel__Certificates__Default__Path='/https/https.pfx' \
        -e ASPNETCORE_Kestrel__Certificates__Default__Password='P@ssw0rd1!' \
        -v <absolute-path-to-repo>/EdgeWebApp/modules/EdgeWebApp/https/:/https/ \
        marvingarcia/edgewebapp