#!/bin/bash
# ============================================================
# docker_init.sh — 볼륨 마운트 모드에서 컨테이너 최초 실행 시 1회 실행
#
# 용도: 소스 코드 전체를 -v 마운트했을 때,
#       editable 패키지와 CuRoPE 커널이 이미지 빌드 당시 것으로
#       덮어씌워지므로 재설치/재빌드가 필요.
#
# 사용법 (컨테이너 내부):
#   bash docker_init.sh
# ============================================================
set -e

MARKER_FILE="/workspace/venv/.docker_init_done"

if [ -f "$MARKER_FILE" ]; then
    echo "=== [SKIP] Already initialized ==="
    exit 0
fi

# diff-gaussian-rasterization: Docker 빌드 시 GPU 없이 컴파일된 바이너리 →
# 실제 GPU(sm_89)에서 illegal memory access. 컨테이너 안에서 재빌드 필요.
echo "=== Rebuilding diff-gaussian-rasterization for GPU compute capability ==="
pip install --force-reinstall --no-cache-dir --no-build-isolation \
    git+https://github.com/byeongjun-park/diff-gaussian-rasterization

echo "=== CuRoPE kernel build ==="
CUROPE_DIR="/workspace/SteerX/steerx_diffusers/geometry_steering/croco/models/curope"
cd "$CUROPE_DIR"
python setup.py build_ext --inplace
cd /workspace/SteerX

touch "$MARKER_FILE"
echo "=== Done! Ready to run SteerX ==="
