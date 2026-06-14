#!/bin/bash

set -euo pipefail

UPLOAD_URL="https://dxmedia.hopto.org/upload.php"
API_KEY="MySecretUploadKey"

find /var/www/html/newperformance -type f -name "*.json" | while read -r FILE
do
echo "Uploading: $FILE"

```
RESPONSE=$(curl -k -s \
    -F "apikey=${API_KEY}" \
    -F "file=@${FILE}" \
    "${UPLOAD_URL}")

if [[ "$RESPONSE" == "OK" ]]; then
    echo "SUCCESS: $FILE"
else
    echo "FAILED: $FILE"
    echo "Response: $RESPONSE"
fi
```

done

