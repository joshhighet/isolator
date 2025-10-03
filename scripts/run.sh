if docker info --format '{{.Runtimes}}' | grep -q "runsc"; then
    echo "using gvisor runtime"
    RUNTIME_SCFLAG="--runtime=runsc"
else
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "gvisor runtime not detected - you should use gvisor for enhanced isolation"
        echo "ref: https://gvisor.dev/docs/user_guide/install/#install-latest"
        echo "using default runtime"
    fi
    RUNTIME_SCFLAG=""
fi

docker run --platform linux/amd64 $RUNTIME_SCFLAG \
--publish 6080:6080 \
--publish 9222:9222 \
--volume "$(pwd)/mount:/mount" \
--security-opt no-new-privileges \
--cap-drop NET_RAW \
--cap-drop SYS_PTRACE \
--cap-drop AUDIT_WRITE \
--cap-drop MKNOD \
--env DEBUG_MODE=false \
--env USE_CLOUDFLARE_TUNNEL=false \
--env EXPOSE_REMOTE_DEBUGGER=false \
--env BROWSER_URL=http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion \
--env RECORD_VIDEO=false \
--env VNC_RESOLUTION=1280x720 \
--env PASSTHROUGH_AUTH=true \
isolator
