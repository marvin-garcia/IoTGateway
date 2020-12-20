#! /bin/sh

docker rm -f edgewebapp
docker run \
        -d \
        --name edgewebapp \
        -p 5001:443 \
        -p 5000:80 \
        -v /mnt/c/Users/magar/source/repos/IoTGateway/EdgeWebApp/modules/EdgeWebApp/https/:/https/ \
        marvingarcia/edgewebapp