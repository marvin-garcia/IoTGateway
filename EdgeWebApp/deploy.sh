az iot edge deployment create \
    --layered true \
    --priority <highest-priority> \
    --deployment-id edgewebapp-<highes-priority> \
    --hub-name <hub-name> \
    --target-condition "<tags-target-condition>" \
    --content layered.manifest.json