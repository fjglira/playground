droute send --metadata result_example/ambient_passed/ossm_report_portal.json \
        --results 'result_example/ambient_passed/junit_master-istio-integration-sail-ambient.xml' \
        --username ossm-oidc-sa \
        --password b71a69cc-880e-432f-8d6e-cd2a4c89d8e4 \
        --url  https://datarouter.ccitredhat.com \
        --verbose \
        --wait