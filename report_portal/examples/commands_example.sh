curl -Ss --fail-with-body --request POST 'https://auth.redhat.com/auth/realms/EmployeeIDP/protocol/openid-connect/token' \
    --data grant_type=client_credentials \
    --data scope=openid \
    --data client_id=ossm-oidc-sa \
    --data client_secret=b71a69cc-880e-432f-8d6e-cd2a4c89d8e4 \
    | jq -r '.access_token' | jq -R 'split(".") | .[0],.[1] | @base64d | fromjson'


droute send --metadata ossm_report_portal.json \
        --results 'result_example/junit_telemetry_istio.xml' \
        --username ossm-oidc-sa \
        --password b71a69cc-880e-432f-8d6e-cd2a4c89d8e4 \
        --url  https://datarouter.ccitredhat.com \
        --verbose \
        --wait