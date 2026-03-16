    docker build -f Dockerfile.py312 -t oakapp-test .


app for testing shutdown behaviour

    docker run --name oakapp-test \
      -v "$(pwd)/test/shutdown_behaviour.py:/app/main.py:ro" \
      -e OAKAPP_MAIN_PY_PATH=/app/main.py \
      --entrypoint /entrypoint.sh \
      oakapp-test

app for testing app exception behaviour

    docker run --name oakapp-test \
      -v "$(pwd)/test/app_exception_behaviour.py:/app/main.py:ro" \
      -e OAKAPP_MAIN_PY_PATH=/app/main.py \
      --entrypoint /entrypoint.sh \
      oakapp-test


Kill

    docker kill --signal=KILL oakapp-test

or

    docker kill oakapp-test


Graceful Shutdown
    
    docker kill --signal=TERM oakapp-test

or

    docker stop oakapp-test


Run in between tests

    docker rm oakapp-test
