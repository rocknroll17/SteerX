#!/bin/bash
# ============================================================
# run_steerx.sh — OOM 안전장치가 포함된 SteerX 컨테이너 실행
#
# 안전 장치:
#   1. GPU 0,1,2만 사용 (GPU 3은 여유분으로 보존)
#   2. 컨테이너 RAM ≤ 200GB (시스템 51GB 보존)
#   3. shared memory 16GB (PyTorch DataLoader 필수)
#   4. Python 레벨 GPU 메모리 92% 상한 (set_per_process_memory_fraction)
#   5. OOM 킬러 우선순위 조정 (--oom-score-adj=500)
#
# 사용법:
#   chmod +x run_steerx.sh
#   sudo ./run_steerx.sh            # 기본: 소스 마운트 모드
#   sudo ./run_steerx.sh --baked    # 이미지 내장 코드 모드
# ============================================================
set -e

CONTAINER_NAME="steerx"
IMAGE_NAME="steerx:latest"
STEERX_DIR="/home/jyc/SteerX"

# 기존 컨테이너 정리
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[INFO] 기존 '${CONTAINER_NAME}' 컨테이너 제거 중..."
    sudo docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    sudo docker rm "${CONTAINER_NAME}" 2>/dev/null || true
fi

# 모드 선택
if [[ "$1" == "--baked" ]]; then
    echo "[MODE] 이미지 내장 코드 모드 (빌드 시점의 코드 사용)"
    MOUNT_ARGS="-v ${STEERX_DIR}/steerx_ckpt:/workspace/SteerX/steerx_ckpt"
    NEED_INIT=false
else
    echo "[MODE] 소스 마운트 모드 (호스트 코드 변경 즉시 반영)"
    MOUNT_ARGS="-v ${STEERX_DIR}:/workspace/SteerX"
    NEED_INIT=true
fi

echo "[INFO] 컨테이너 생성 중..."
sudo docker run \
    --gpus '"device=1,2"' \
    -dit \
    --name "${CONTAINER_NAME}" \
    ${MOUNT_ARGS} \
    --shm-size=16g \
    --memory=200g \
    --memory-swap=200g \
    --oom-score-adj=500 \
    "${IMAGE_NAME}" bash

# 소스 마운트 모드: editable 패키지 + CuRoPE 자동 재빌드
if [[ "$NEED_INIT" == true ]]; then
    echo "[INFO] 소스 마운트 초기화 중 (SAM2, viser, CuRoPE)..."
    sudo docker exec "${CONTAINER_NAME}" bash /workspace/SteerX/docker_init.sh
fi

echo ""
echo "========================================"
echo "  SteerX 컨테이너 '${CONTAINER_NAME}' 생성 완료"
echo "========================================"
echo ""
echo "접속:  sudo docker exec -it ${CONTAINER_NAME} bash"
if [[ "$1" != "--baked" ]]; then
    echo "  (소스 마운트 초기화가 자동 실행됩니다. 1~2분 소요)"
fi
echo ""
echo "실행 예시 (컨테이너 내부):"
echo "  # SplatFlow (가장 작은 모델, 테스트용)"
echo "  python demo_steerx.py --model splatflow --num_particles 1 \\"
echo "    --prompt 'a delicious hamburger on a wooden table'"
echo ""
echo "  # Mochi (큰 모델)"
echo "  python demo_steerx.py --model mochi --num_particles 2 \\"
echo "    --prompt 'a penguin walking on the beach'"
echo ""
echo "GPU 모니터링 (호스트에서):"
echo "  watch -n 1 nvidia-smi"
echo ""
